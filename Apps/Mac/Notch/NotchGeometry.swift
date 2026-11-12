import AppKit

/// Where the notch is on a screen. Screens without one get a virtual notch at the top center.
struct NotchGeometry: Equatable {
    var notchSize: CGSize
    var hasHardwareNotch: Bool
    var screenFrame: CGRect

    @MainActor
    init(screen: NSScreen) {
        screenFrame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasHardwareNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            hasHardwareNotch = false
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            notchSize = CGSize(width: 180, height: min(menuBar, 32))
        }
    }

    /// A made-up screen, for drawing the notch in a snapshot.
    init(notchSize: CGSize, hasHardwareNotch: Bool, screenFrame: CGRect) {
        self.notchSize = notchSize
        self.hasHardwareNotch = hasHardwareNotch
        self.screenFrame = screenFrame
    }

    /// A panel of this size, centered at the top edge. AppKit's origin is the bottom left.
    func frame(for size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
