import Foundation
import CoreGraphics
import StatsCore

struct TrayTests {
    func testNotchAndRightEdge() throws {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 68, width: 1512, height: 877)
        let frame = TrayLayout.frame(anchorX: 1490, screen: screen, visible: visible,
                                     safeTop: 38, size: CGSize(width: 560, height: 362))
        try expectTrue(frame.maxY <= screen.maxY - 38 - 8)
        try expectTrue(frame.maxX <= screen.maxX - 12)
        try expectTrue(visible.contains(frame))
    }

    func testExternalDisplayWithNegativeOrigin() throws {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: 200, width: 1920, height: 1056)
        let frame = TrayLayout.frame(anchorX: -1910, screen: screen, visible: visible,
                                     safeTop: 0, size: CGSize(width: 560, height: 362))
        try expectEqual(frame.minX, -1908)
        try expectTrue(visible.contains(frame))
    }

    func testSmallDisplayAndSideDock() throws {
        let screen = CGRect(x: 0, y: 0, width: 640, height: 360)
        let visible = CGRect(x: 80, y: 0, width: 560, height: 336)
        let frame = TrayLayout.frame(anchorX: 10, screen: screen, visible: visible,
                                     safeTop: 0, size: CGSize(width: 560, height: 362))
        try expectTrue(visible.contains(frame))
        try expectTrue(frame.minX >= 92)
        try expectTrue(frame.height > 0)
        try expectTrue(frame.width <= 536)
    }

    func testAutohiddenMenuStillAvoidsNotch() throws {
        let screen = CGRect(x: 400, y: -900, width: 1512, height: 982)
        let frame = TrayLayout.frame(anchorX: 900, screen: screen, visible: screen,
                                     safeTop: 38, size: CGSize(width: 560, height: 362))
        try expectTrue(frame.maxY <= screen.maxY - 46)
    }

    func testOrderHandlesRelaunchesAndNewItems() throws {
        try expectEqual(TrayOrder.arrange(["a", "c", "b", "d", "a"], saved: ["b", "closed", "a", "b"]),
                        ["b", "a", "c", "d"])
        try expectEqual(TrayOrder.arrange([], saved: ["old"]), [])
    }
}
