import Foundation
import PerchKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Serves bundled web assets and vault files to the web view through private URL schemes.
final class PerchSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Where the notebook is. Set after the fact for a page that was loaded before anyone needed it.
    var vaultRoot: () -> URL?
    private let webRoot: URL

    init(vaultRoot: @escaping () -> URL?) {
        self.vaultRoot = vaultRoot
        webRoot = WebHost.bundledWebRoot
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = resolve(url), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var headers = [
            "Content-Type": type,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
        ]
        // The page's own files never change while the app runs, so later pages take them from memory.
        if url.scheme == "perch-app" { headers["Cache-Control"] = "max-age=31536000, immutable" }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func resolve(_ url: URL) -> URL? {
        let relative = url.path.removingPercentEncoding ?? url.path
        let base: URL?
        switch url.scheme {
        case "perch-app": base = webRoot
        case "perch-vault": base = vaultRoot()
        default: base = nil
        }
        guard let base else { return nil }
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        // A note can't read anything outside its vault with a `../` path.
        guard target.path.hasPrefix(root.path + "/") else { return nil }
        return target
    }
}

/// Owns one web view and the messages between it and Swift.
@MainActor
public final class WebHost: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: WKWebView
    public var onMessage: (([String: Any]) -> Void)?
    private let handler: PerchSchemeHandler
    private var isReady = false
    private var pending: [() -> Void] = []
    private let pageURL: URL
    /// The last note this page was asked to draw, to draw again if the system kills the page's process.
    private var lastRender: [String: Any]?
    private var pageDied = false
    /// The last appearance the page was given, to give it again after `unload`.
    private var lastAppearance: [String: Any]?
    /// True while the page has been let go because nothing was showing it. See `ReaderIdle`.
    public private(set) var isUnloaded = false
    private var idleCheck: Task<Void, Never>?
    /// When the page was asked for and when it said it was ready, for timing how long a note takes to open.
    public let createdAt = Date()
    public private(set) var readyAt: Date?
    /// When a view took this page for its own, and when the page first said a note's text was on screen.
    public private(set) var takenAt = Date()
    public private(set) var firstTextAt: Date?
    #if DEBUG
    /// Every live page, for the debug snapshot runner.
    public static var debugHosts = NSHashTable<WebHost>.weakObjects()
    public let debugPage: String
    /// What the page last said about how long drawing took, for the debug snapshot runner.
    public private(set) var debugTiming: [String: Any] = [:]
    #endif

    /// The folder of built pages inside the app.
    static var bundledWebRoot: URL { (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Web") }

    /// One in-memory store for every page: nothing is kept on disk, and pages share what they have
    /// already fetched, so the second page to open doesn't read and compile the scripts again.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    // MARK: A reader kept ready

    /// A reader page that is already loaded, waiting for the next note or task to be opened.
    private static var spareReader: WebHost?
    private static var spareIsQueued = false
    private static var watchesMemory = false

    /// Lets go of the spare page. The next note to open makes its own, as notes did before there was a spare.
    static func dropSpareReader() {
        spareReader = nil
    }

    /// On iPhone and iPad a page waiting unused is the first thing to give back when memory runs short.
    private static func watchMemory() {
        guard !watchesMemory else { return }
        watchesMemory = true
        #if os(iOS)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { dropSpareReader() }
        }
        #endif
    }

    /// Loads a reader page ahead of need, so opening a note doesn't wait for a web view to start.
    /// Safe to call often: there is only ever one spare. Does nothing where there are no pages to load (tests).
    public static func prewarmReader() {
        guard spareReader == nil, !spareIsQueued, FileManager.default.fileExists(atPath: bundledWebRoot.appendingPathComponent("render.html").path) else { return }
        spareIsQueued = true
        watchMemory()
        // After the current work, not in the middle of it: a view that is opening right now comes first.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            spareIsQueued = false
            if spareReader == nil { spareReader = WebHost(page: "render") { nil } }
        }
    }

    /// A reader page for notes or task details: the one kept ready if there is one, a new one otherwise.
    /// Another is made ready straight afterwards.
    public static func reader(vaultRoot: @escaping () -> URL?) -> WebHost {
        defer { prewarmReader() }
        // A spare whose page has died (the system took its process back) is no use to anyone.
        guard let host = spareReader, !host.pageDied else {
            spareReader = nil
            let fresh = WebHost(page: "render", vaultRoot: vaultRoot)
            fresh.watchIdle()
            return fresh
        }
        spareReader = nil
        host.takenAt = Date()
        host.handler.vaultRoot = vaultRoot
        host.watchIdle()
        return host
    }

    // MARK: A page nobody is looking at

    /// The web view came on screen or left it. Off screen, a reader page is given `ReaderIdle.limit`
    /// seconds and then let go; back on screen, it is loaded and drawn again.
    private func windowChanged(onScreen: Bool) {
        idleCheck?.cancel()
        idleCheck = nil
        if onScreen { restore() } else { watchIdle() }
    }

    /// Starts the clock for a page that isn't on screen. A page that is taken by a view and never shown
    /// is on the same clock as one that was shown and then hidden.
    private func watchIdle() {
        guard pageURL.lastPathComponent == "render.html", webView.window == nil, !isUnloaded, idleCheck == nil else { return }
        let since = Date()
        idleCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((ReaderIdle.limit + 0.5) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.idleCheck = nil
            let unloads = ReaderIdle.unloads(
                offScreenFor: Date().timeIntervalSince(since), isOnScreen: self.webView.window != nil,
                isSpare: Self.spareReader === self, isUnloaded: self.isUnloaded
            )
            if unloads { self.unload() }
        }
    }

    /// Lets the page go: its document, scripts and everything it drew are dropped, and the web view
    /// stays, empty. Whatever still holds this host holds very little.
    private func unload() {
        isUnloaded = true
        isReady = false
        pending = []
        webView.loadHTMLString("", baseURL: nil)
    }

    #if DEBUG
    public func debugUnload() { unload() }
    public func debugRestore() { restore() }
    var debugLastRender: [String: Any]? { lastRender }
    var debugPendingCount: Int { pending.count }
    #endif

    /// Loads the page again and shows it what it had: its appearance, then the note.
    private func restore() {
        guard isUnloaded else { return }
        isUnloaded = false
        if let lastAppearance { call("setAppearance", arguments: lastAppearance) }
        if let lastRender { call("render", arguments: lastRender) }
        webView.load(URLRequest(url: pageURL))
    }

    public init(page: String, vaultRoot: @escaping () -> URL?) {
        let configuration = WKWebViewConfiguration()
        handler = PerchSchemeHandler(vaultRoot: vaultRoot)
        configuration.setURLSchemeHandler(handler, forURLScheme: "perch-app")
        configuration.setURLSchemeHandler(handler, forURLScheme: "perch-vault")
        // Pages run in memory only: no cookies or site data are kept.
        configuration.websiteDataStore = Self.dataStore
        // On the Mac, Perch's own web view, which also decides where scroll-wheel events go (see WebScroll).
        #if os(macOS)
        let view: HostedWebView = PerchWebView(frame: .zero, configuration: configuration)
        #else
        let view = HostedWebView(frame: .zero, configuration: configuration)
        #endif
        webView = view
        pageURL = URL(string: "perch-app://app/\(page).html")!
        #if DEBUG
        debugPage = page
        #endif
        super.init()
        #if DEBUG
        webView.isInspectable = true
        Self.debugHosts.add(self)
        #endif
        configuration.userContentController.add(WeakMessageHandler(self), name: "perch")
        view.onWindowChange = { [weak self] onScreen in self?.windowChanged(onScreen: onScreen) }
        webView.navigationDelegate = self
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        webView.load(URLRequest(url: pageURL))
    }

    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            isReady = true
            readyAt = Date()
            // Emptied first: a queued call may queue another.
            let waiting = pending
            pending = []
            waiting.forEach { $0() }
        }
        if type == "rendered", firstTextAt == nil { firstTextAt = Date() }
        #if DEBUG
        if type == "rendered" || type == "settled", let timing = body["timing"] as? [String: Any] { debugTiming = timing }
        #endif
        onMessage?(body)
    }

    /// Passes data as a real argument, so note text can't break out of the script.
    public func call(_ function: String, arguments: [String: Any]) {
        if function == "render" { lastRender = arguments }
        if function == "setAppearance" { lastAppearance = arguments }
        // A page that has been let go is told again when it comes back; see `restore`.
        if isUnloaded { return }
        let run = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                _ = try? await self.webView.callAsyncJavaScript(
                    "return await window.Perch.\(function)(payload);",
                    arguments: ["payload": arguments],
                    contentWorld: .page
                )
            }
        }
        if isReady { run() } else { pending.append(run) }
    }

    public func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // The page itself, loaded by this class and never by a link; and frames inside it (a video embed).
        let isOwnPage = action.request.url == pageURL && action.navigationType != .linkActivated && action.navigationType != .formSubmitted
        // The empty page that takes its place while nobody is looking; see `unload`.
        let isEmptyPage = isUnloaded && action.request.url?.absoluteString == "about:blank" && action.navigationType == .other
        if isOwnPage || isEmptyPage || action.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
        } else {
            // Nothing else may replace the page. A link the page's own listener didn't stop opens outside only
            // when it is a web page or an email address; tel:, file:, another app's scheme and the rest go nowhere.
            decisionHandler(.cancel)
            if let url = action.request.url, action.navigationType == .linkActivated, ExternalLink.opens(url) { PlatformOpen.url(url) }
        }
    }

    /// The system can take a page's process back at any time, most often on iPhone while the app is in the
    /// background. The page is loaded again and shown the note it had, instead of staying blank.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if Self.spareReader === self {
            Self.spareReader = nil
            return
        }
        // A page that was let go has nothing to bring back until it is shown again.
        guard !isUnloaded else { return }
        // Twice in a row means something is wrong with the page itself; don't loop.
        guard !pageDied else { return }
        pageDied = true
        isReady = false
        pending = []
        if let lastRender {
            pending.append { [weak self] in
                self?.pageDied = false
                self?.call("render", arguments: lastRender)
            }
        } else {
            pending.append { [weak self] in self?.pageDied = false }
        }
        webView.load(URLRequest(url: pageURL))
    }

    /// Waits until the page has finished drawing everything it was last asked to render: code coloured,
    /// formulas typeset, diagrams drawn. For anything that takes a picture of the page, such as a PDF.
    public func settle() async {
        var waited = 0
        while !isReady, waited < 100 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        _ = try? await webView.callAsyncJavaScript("return await window.Perch.settle();", arguments: [:], contentWorld: .page)
    }

    public func makePDF() async -> Data? {
        try? await webView.pdf()
    }
}

/// When a reader page that nobody is looking at is let go.
///
/// A closed note's page should be freed with its view. This is the safety net for when something
/// still holds the view: a page with a note drawn in it is tens of megabytes and a process of its
/// own, and after half a minute off screen it gives them back. Tabs that aren't in front have no page
/// at all (their views aren't kept), so they need no rule here.
public enum ReaderIdle {
    /// Seconds off screen before a page is let go.
    public static let limit: TimeInterval = 30

    /// - Parameters:
    ///   - isSpare: the page kept ready for the next note. It is off screen by design and stays.
    public static func unloads(offScreenFor seconds: TimeInterval, isOnScreen: Bool, isSpare: Bool, isUnloaded: Bool) -> Bool {
        !isOnScreen && !isSpare && !isUnloaded && seconds >= limit
    }
}

/// A web view that says when it comes on screen and when it leaves. On the Mac, PerchWebView builds on it.
class HostedWebView: WKWebView {
    var onWindowChange: ((Bool) -> Void)?

    #if os(macOS)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window != nil)
    }
    #else
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
    #endif
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

public extension PerchTheme {
    /// The theme as part of the argument for `Perch.setAppearance` in the render page: its colours as CSS
    /// variables, and whether it is light or dark.
    /// - Parameter paintsBackground: false leaves the page see-through, for a render that sits on a card.
    func webAppearance(paintsBackground: Bool = true) -> [String: Any] {
        var variables = cssVariables.filter { $0.key.hasPrefix("--") }
        // An empty value clears the variable, and the page stays transparent.
        if !paintsBackground { variables["--perch-bg"] = "" }
        return ["variables": variables, "colorScheme": isDark ? "dark" : "light"]
    }
}

public enum PlatformOpen {
    /// Puts text on the clipboard, for the reader's Copy buttons.
    @MainActor
    public static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// Opens a web page in the browser or an email address in Mail. Any other address is dropped (see `ExternalLink`).
    @MainActor
    public static func url(_ url: URL) {
        guard ExternalLink.opens(url) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

/// A web view in SwiftUI. `embedded` is for one inside a scroll view that only shows what fits, like a task's
/// details: scrolling over it then scrolls what is around it. See WebScroll.
#if os(macOS)
struct WebHostView: NSViewRepresentable {
    let host: WebHost
    var embedded = false
    func makeNSView(context: Context) -> WKWebView {
        (host.webView as? PerchWebView)?.passesScrollToParent = embedded
        return host.webView
    }
    func updateNSView(_ view: WKWebView, context: Context) { (view as? PerchWebView)?.passesScrollToParent = embedded }
}
#else
struct WebHostView: UIViewRepresentable {
    let host: WebHost
    var embedded = false
    func makeUIView(context: Context) -> WKWebView {
        // An embedded page never scrolls by itself, so swipes over it move what is around it.
        if embedded { host.webView.scrollView.isScrollEnabled = false }
        return host.webView
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
