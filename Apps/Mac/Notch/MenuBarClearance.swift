import AppKit
import ApplicationServices

/// Works out whether menus or menu bar icons reach into the space beside the notch,
/// so Perch's counts never cover them.
@MainActor
enum MenuBarClearance {
    /// True when Perch may read other apps' menu bar layout (System Settings → Privacy → Accessibility).
    static var canMeasureMenus: Bool { AXIsProcessTrusted() }

    static func requestMenuAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Whether the band `earWidth` wide on each side of the notch is free on `screen`.
    static func isClear(screen: NSScreen, notch: CGRect, earWidth: CGFloat) -> Bool {
        let left = CGRect(x: notch.minX - earWidth - 6, y: notch.minY, width: earWidth + 6, height: notch.height)
        let right = CGRect(x: notch.maxX, y: notch.minY, width: earWidth + 6, height: notch.height)
        return !statusItemsOverlap(right, screen: screen) && !appMenusOverlap(left)
    }

    /// Menu bar icons are their own windows, so their positions are public.
    private static func statusItemsOverlap(_ band: CGRect, screen: NSScreen) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let level = Int(CGWindowLevelForKey(.statusWindow))
        for info in windows where (info[kCGWindowLayer as String] as? Int) == level {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) != ProcessInfo.processInfo.processIdentifier,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: mainHeight - (bounds["Y"] ?? 0) - (bounds["Height"] ?? 0),
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.intersects(band) { return true }
        }
        return false
    }

    /// The frontmost app's menus are only visible through Accessibility. Without it, only
    /// Finder and Perch, whose menus are known to be short, count as clear.
    private static func appMenusOverlap(_ band: CGRect) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }
        guard canMeasureMenus else { return app.bundleIdentifier != "com.apple.finder" }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              let bar = menuBar else { return false }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return false }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for item in items {
            var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success else { continue }
            var point = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            let rect = CGRect(x: point.x, y: mainHeight - point.y - size.height, width: size.width, height: size.height)
            if rect.intersects(band) { return true }
        }
        return false
    }
}
