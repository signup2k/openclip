import XCTest
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    func testSharedDisplayEdgesPreferActualContainingDisplayOverTolerance() {
        let left = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1200, height: 900)
        for screens in [[left, right], [right, left]] {
            XCTAssertEqual(PopupPositioner.screenFrame(containing: CGPoint(x: -1, y: 400), screenFrames: screens), left)
            XCTAssertEqual(PopupPositioner.screenFrame(containing: CGPoint(x: 1, y: 400), screenFrames: screens), right)
            XCTAssertEqual(PopupPositioner.screenFrame(containing: CGPoint(x: 0, y: 400), screenFrames: screens), right)
        }
    }

    func testRadialSubBarFlipsToTheOppositeDiskEdge() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let disk = CGRect(x: 300, y: 438, width: 144, height: 144)
        let height: CGFloat = 50
        let result = PopupPositioner.subBarY(anchor: disk, height: height, preferAbove: true, screenBounds: screen)
        XCTAssertFalse(result.above)
        XCTAssertLessThan(result.y + height - PopupMetrics.popupShadowInset, disk.minY)
    }

    func testRadialPlacementCentersAtCursorAndClampsEveryScreenEdge() {
        let screen = CGRect(x: -1200, y: -300, width: 1000, height: 800)
        let size = CGSize(width: 232, height: 232)
        let center = CGPoint(x: screen.midX, y: screen.midY)
        let centered = PopupPositioner.placeAroundCursor(center, popupSize: size, screenBounds: screen)
        XCTAssertEqual(centered.midX, center.x)
        XCTAssertEqual(centered.midY, center.y)
        for x in [screen.minX, screen.maxX] {
            for y in [screen.minY, screen.maxY] {
                let frame = PopupPositioner.placeAroundCursor(CGPoint(x: x, y: y), popupSize: size, screenBounds: screen)
                XCTAssertTrue(screen.insetBy(dx: PopupMetrics.popupPadding, dy: PopupMetrics.popupPadding).contains(frame))
                XCTAssertEqual(frame.size, size)
            }
        }
    }

    private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let size = CGSize(width: 50, height: 50)

    // Near top edge: popup should flip BELOW the release point
    func testTopEdgeFlipToBelow() {
        let release = CGPoint(x: 400, y: 580)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // No room above (580+6+50=636 > 600-8=592), flip below: 580 - 50 - 6 = 524
        XCTAssertEqual(frame.origin.y, 524)
    }

    func testVerticalPositionBelowForcesPlacementBelow() {
        // With an upward/horizontal drag, .below forces placement below
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release,
            popupSize: size,
            screenBounds: screen,
            verticalPosition: .below
        )
        // Below release: 200 - 50 - 6 = 144
        XCTAssertEqual(frame.origin.y, 144)
        XCTAssertFalse(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
    }

    func testVerticalPositionBelowFlipsWhenNearBottomEdge() {
        let release = CGPoint(x: 400, y: 30)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release,
            popupSize: size,
            screenBounds: screen,
            verticalPosition: .below
        )
        // No room below (30 - 50 - 6 = -26 < 8), flips above: 30 + 6 = 36
        XCTAssertEqual(frame.origin.y, 36)
        XCTAssertTrue(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
    }

    func testSearchPaletteMidXClampedByScreenEdges() {
        let screenBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let padding = PopupMetrics.popupPadding
        let searchWidth: CGFloat = 312

        // When barMaxX is very small (near left screen edge)
        let leftMidX = PopupPositioner.searchPaletteMidX(
            buttonScreenMidX: 50,
            searchWidth: searchWidth,
            barMaxX: 100,
            screenBounds: screenBounds
        )
        // Screen padding takes precedence so it never renders off-screen
        XCTAssertEqual(leftMidX, screenBounds.minX + padding + searchWidth / 2)
    }
}
