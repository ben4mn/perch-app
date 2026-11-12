import AppKit
import UniformTypeIdentifiers
import WebKit
import XCTest

/// Where things live in the checkout, found from this file's own path.
enum Checkout {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// The built reader page the apps ship. `PERCH_WEB_ROOT` points the tests at another build, for comparing timings.
    static var web: URL {
        if let other = ProcessInfo.processInfo.environment["PERCH_WEB_ROOT"] { return URL(fileURLWithPath: other) }
        return root.appendingPathComponent("Apps/Shared/Web")
    }
    static let fixtures = root.appendingPathComponent("Tests/Fixtures/Rendering")

    static func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }
}

/// Serves the page and a pretend notebook through the same private schemes the apps use.
private final class TestSchemeHandler: NSObject, WKURLSchemeHandler {
    let webRoot: URL
    var vaultRoot: URL?
    var requested: [String] = []
    /// Addresses containing any of these fail to load, as they would with a damaged install.
    var failing: [String] = []

    init(webRoot: URL, vaultRoot: URL?) {
        self.webRoot = webRoot
        self.vaultRoot = vaultRoot
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let url = task.request.url!
        requested.append(url.absoluteString)
        let base = url.scheme == "perch-app" ? webRoot : vaultRoot
        let relative = url.path.removingPercentEncoding ?? url.path
        guard !failing.contains(where: { url.absoluteString.contains($0) }), let base, let data = try? Data(contentsOf: base.appendingPathComponent(relative)) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store",
        ])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Lets the reader page load and nothing else, and writes down every address it turned away. This is `WebHost`'s
/// rule made stricter: the app also lets frames inside the page load (a video embed), and a test page needs none.
///
/// A web view with no navigation delegate hands any address WebKit can't load itself (`tel:`, another app's
/// scheme) to the system. A click on the `tel:` link in xss-more.md once made every test run offer to place a call.
private final class TestNavigationGuard: NSObject, WKNavigationDelegate {
    let pageURL: URL
    /// Every navigation turned away, oldest first.
    var refused: [URL] = []

    init(pageURL: URL) { self.pageURL = pageURL }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // The page itself, loaded by `RenderPage` (or loaded again by `startOver`) and never by a link.
        let isOwnPage = action.request.url == pageURL && action.navigationType != .linkActivated && action.navigationType != .formSubmitted
        if isOwnPage {
            decisionHandler(.allow)
            return
        }
        // Everything else stays here, frames included: nothing a test page does reaches the system.
        if let url = action.request.url { refused.append(url) }
        decisionHandler(.cancel)
    }
}

/// One reader page in an offscreen window, driven the way `WebHost` drives it.
///
/// A test run can put only so many web views in offscreen windows: the 64th never loads its page,
/// whether or not the earlier ones are still alive, and the tests make far more pages than that. So a
/// closed page's web view stays in its window and is handed to the next page, which loads the reader
/// in it again from nothing: no note, no libraries, and nothing cached (the files are served `no-store`).
@MainActor
final class RenderPage: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    private let window: NSWindow
    private let handler: TestSchemeHandler
    private let navigation: TestNavigationGuard
    private(set) var messages: [[String: Any]] = []
    let created = Date()
    private(set) var readyAfter: TimeInterval?

    static let pageURL = URL(string: "perch-app://app/render.html")!
    /// The guard goes with its web view, so a web view waiting here for its next page is never without one.
    private static var closed: [(webView: WKWebView, window: NSWindow, handler: TestSchemeHandler, navigation: TestNavigationGuard)] = []
    /// How many web views the tests have made in this process.
    private(set) static var webViewsMade = 0

    /// - Parameter newWebView: true makes a web view of its own, for timing how long a new one takes to load.
    init(width: CGFloat = 760, height: CGFloat = 800, vaultRoot: URL? = nil, newWebView: Bool = false) {
        _ = NSApplication.shared
        if !newWebView, let kept = Self.closed.popLast() {
            (webView, window, handler, navigation) = kept
            handler.vaultRoot = vaultRoot
            handler.requested = []
            handler.failing = []
            navigation.refused = []
            window.setContentSize(NSSize(width: width, height: height))
            webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        } else {
            let configuration = WKWebViewConfiguration()
            handler = TestSchemeHandler(webRoot: Checkout.web, vaultRoot: vaultRoot)
            configuration.setURLSchemeHandler(handler, forURLScheme: "perch-app")
            configuration.setURLSchemeHandler(handler, forURLScheme: "perch-vault")
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
            navigation = TestNavigationGuard(pageURL: Self.pageURL)
            webView.navigationDelegate = navigation
            window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = webView
            window.orderBack(nil)
            Self.webViewsMade += 1
        }
        super.init()
        webView.configuration.userContentController.add(self, name: "perch")
        webView.load(URLRequest(url: Self.pageURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func close() {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        // The window stays where it is: taking it away and putting it back counts toward the limit too.
        Self.closed.append((webView, window, handler, navigation))
    }

    var requestedURLs: [String] { handler.requested }
    /// Every address the page tried to go to and was kept from, oldest first. None of them reached the system.
    var refusedNavigations: [URL] { navigation.refused }
    /// Makes files whose address contains one of these fail to load from now on. Empty lets everything load again.
    func failRequests(containing parts: [String]) { handler.failing = parts }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "ready", readyAfter == nil { readyAfter = Date().timeIntervalSince(created) }
        messages.append(body)
    }

    /// Loads the page again from nothing: no note, no caches, no libraries. Cheaper than a new web view,
    /// and WebKit stops answering after a few hundred of those in one process.
    func startOver() async throws {
        readyAfter = nil
        messages = []
        webView.reload()
        try await ready()
    }

    func messages(ofType type: String) -> [[String: Any]] { messages.filter { $0["type"] as? String == type } }
    func clearMessages() { messages = [] }

    func wait(_ what: String, timeout: TimeInterval = 30, until done: () -> Bool) async throws {
        let start = Date()
        while !done() {
            if Date().timeIntervalSince(start) > timeout { throw NSError(domain: "RenderPage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(what)"]) }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func ready() async throws {
        do { try await wait("the page to load") { readyAfter != nil } } catch {
            print("The page didn't load. Web views made:", Self.webViewsMade, "requested:", handler.requested, "loading:", webView.isLoading, "url:", webView.url as Any, "progress:", webView.estimatedProgress, "messages:", messages.count)
            throw error
        }
    }

    /// Calls `window.Perch.<function>(payload)` exactly as the app does.
    @discardableResult
    func call(_ function: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript("return await window.Perch.\(function)(payload);", arguments: ["payload": arguments], contentWorld: .page)
    }

    /// Runs a function body in the page and returns what it returns.
    func js(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
    }

    /// Renders and waits until every code block, formula and diagram has been drawn.
    func render(_ markdown: String, _ extra: [String: Any] = [:]) async throws {
        try await ready()
        var arguments: [String: Any] = ["markdown": markdown, "basePath": "note.md"]
        arguments.merge(extra) { _, new in new }
        try await call("render", arguments)
        try await settle()
    }

    func settle() async throws {
        _ = try await js("if (window.Perch.settle) await window.Perch.settle(); return true;")
    }

    func int(_ expression: String) async throws -> Int {
        (try await js("return (\(expression));") as? NSNumber)?.intValue ?? -1
    }

    func string(_ expression: String) async throws -> String {
        try await js("return String(\(expression));") as? String ?? ""
    }

    func count(_ selector: String) async throws -> Int {
        (try await js("return document.querySelectorAll(selector).length;", ["selector": selector]) as? NSNumber)?.intValue ?? -1
    }

    func resize(width: CGFloat, height: CGFloat = 800) async throws {
        window.setContentSize(NSSize(width: width, height: height))
        webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        try await wait("the page to take its new width") {
            false || self.lastWidth == Int(width)
        }
    }

    private var lastWidth: Int {
        var result = -1
        webView.evaluateJavaScript("window.innerWidth") { value, _ in result = (value as? NSNumber)?.intValue ?? -1 }
        // evaluateJavaScript answers on a later turn of the run loop; spin it briefly.
        let until = Date().addingTimeInterval(0.2)
        while result < 0, Date() < until { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
        return result
    }
}
