import Foundation
#if os(macOS)
import AppKit
import WebKit
#endif

/// Where a scroll over a web view goes. A web view inside a scroll view that only shows what fits (a task's
/// details, a sample in Settings) hands up-and-down scrolling to the scroll view around it, so the panel can be
/// scrolled with the pointer anywhere over it, and keeps sideways scrolling for a wide table or code block. A web
/// view that fills its pane (the note reader, a board) scrolls itself. See WebScrollTests.
public enum WebScroll {
    public static func goesToParent(deltaX: CGFloat, deltaY: CGFloat, embedded: Bool) -> Bool {
        embedded && abs(deltaY) >= abs(deltaX)
    }
}

#if os(macOS)
/// Perch's web view. On the Mac a web view keeps scroll-wheel events even when it has nothing to scroll; this
/// one passes them to its scroll view when it is embedded, as WebScroll decides.
final class PerchWebView: HostedWebView {
    var passesScrollToParent = false

    override func scrollWheel(with event: NSEvent) {
        if WebScroll.goesToParent(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, embedded: passesScrollToParent),
           let parent = enclosingScrollView {
            parent.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#endif
