import Foundation
import CoreGraphics

/// AppKit screen coordinates (origin at the bottom left). The tray may span the
/// notch horizontally, but its entire surface stays below the camera/menu bar.
public enum TrayLayout {
    public static func frame(anchorX: CGFloat, screen: CGRect, visible: CGRect,
                             safeTop: CGFloat, size: CGSize) -> CGRect {
        let margin: CGFloat = 12
        let left = max(screen.minX, visible.minX) + margin
        let right = min(screen.maxX, visible.maxX) - margin
        let top = min(visible.maxY, screen.maxY - max(0, safeTop)) - 8
        let bottom = max(screen.minY, visible.minY) + margin
        let width = min(size.width, max(1, right - left))
        let height = min(size.height, max(1, top - bottom))
        let x = max(left, min(anchorX - width / 2, right - width))
        return CGRect(x: x, y: max(bottom, top - height), width: width, height: height)
    }
}

public enum TrayOrder {
    /// Keep saved entries in their chosen order; append newly discovered items
    /// in menu-bar order. Stale saved IDs never create phantom tray buttons.
    public static func arrange(_ discovered: [String], saved: [String]) -> [String] {
        let available = Set(discovered)
        var seen = Set<String>()
        return (saved.filter { available.contains($0) } + discovered).filter { seen.insert($0).inserted }
    }
}
