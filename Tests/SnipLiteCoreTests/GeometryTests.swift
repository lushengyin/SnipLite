import XCTest
@testable import SnipLiteCore

final class ScreenGeometryTests: XCTestCase {
    private func makeGeometry() -> ScreenGeometry {
        ScreenGeometry(cocoaFrames: [
            (CGRect(x: 0, y: 0, width: 1440, height: 900), 2, 1),
            (CGRect(x: 1440, y: 0, width: 1920, height: 1080), 1, 2)
        ])
    }

    func testUnionAndFlippedFrames() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.union, CGRect(x: 0, y: 0, width: 3360, height: 1080))
        XCTAssertEqual(geometry.canvasScale, 2)

        XCTAssertEqual(geometry.screens[0].frame, CGRect(x: 0, y: 180, width: 1440, height: 900))
        XCTAssertEqual(geometry.screens[1].frame, CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }

    func testCoordinateRoundTripBetweenCocoaAndModel() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.toModel(CGPoint(x: 0, y: 1080)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(geometry.toModel(CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 1080))

        let cocoa = CGPoint(x: 900, y: 400)
        let model = geometry.toModel(cocoa)
        XCTAssertEqual(geometry.toCocoa(model), cocoa)
    }

    func testCocoaFrameRoundTrip() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.cocoaFrame(for: geometry.screens[0]),
                       CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(geometry.cocoaFrame(for: geometry.screens[1]),
                       CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }

    func testNegativeOriginScreens() {
        let geometry = ScreenGeometry(cocoaFrames: [
            (CGRect(x: -1920, y: 0, width: 1920, height: 1080), 1, 1),
            (CGRect(x: 0, y: 0, width: 1440, height: 900), 2, 2)
        ])
        XCTAssertEqual(geometry.union, CGRect(x: 0, y: 0, width: 3360, height: 1080))
        XCTAssertEqual(geometry.toModel(CGPoint(x: -1920, y: 1080)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(geometry.toModel(CGPoint(x: 0, y: 1080)), CGPoint(x: 1920, y: 0))
    }

    func testScreenLookupAndPixelSize() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.screen(at: CGPoint(x: 2000, y: 500))?.displayID, 2)
        XCTAssertEqual(geometry.screen(at: CGPoint(x: 200, y: 500))?.displayID, 1)

        // 屏幕 1 是 2x：100×100 点 → 200×200 像素
        let size = geometry.pixelSize(of: CGRect(x: 10, y: 10, width: 100, height: 100))
        XCTAssertEqual(size, CGSize(width: 200, height: 200))
    }

    func testCanvasRectUsesCanvasScale() {
        let geometry = makeGeometry()
        let rect = geometry.canvasRect(for: CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(rect, CGRect(x: 20, y: 40, width: 60, height: 80))
    }
}

final class SelectionModelTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private var model: SelectionModel { SelectionModel(bounds: bounds) }

    func testNormalizeHandlesReverseDrag() {
        let rect = model.normalized(CGPoint(x: 100, y: 100), CGPoint(x: 10, y: 40))
        XCTAssertEqual(rect, CGRect(x: 10, y: 40, width: 90, height: 60))
    }

    func testNormalizeClampsToBounds() {
        let rect = model.normalized(CGPoint(x: -50, y: -50), CGPoint(x: 1200, y: 900))
        XCTAssertEqual(rect, bounds)
    }

    func testHandleHitTest() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let model = SelectionModel(bounds: bounds, selection: selection, handleRadius: 8)

        XCTAssertEqual(model.handle(at: CGPoint(x: 100, y: 100)), .topLeft)
        XCTAssertEqual(model.handle(at: CGPoint(x: 300, y: 200)), .bottomRight)
        XCTAssertEqual(model.handle(at: CGPoint(x: 200, y: 100)), .top)
        XCTAssertNil(model.handle(at: CGPoint(x: 200, y: 150)))
        XCTAssertNil(model.handle(at: CGPoint(x: 100, y: 60)))
    }

    func testResizeBottomRight() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let model = SelectionModel(bounds: bounds, selection: selection)
        let rect = model.resized(.bottomRight, to: CGPoint(x: 350, y: 260))
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 250, height: 160))
    }

    func testResizeTopLeftKeepsOppositeCorner() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let model = SelectionModel(bounds: bounds, selection: selection)
        let rect = model.resized(.topLeft, to: CGPoint(x: 60, y: 50))
        XCTAssertEqual(rect, CGRect(x: 60, y: 50, width: 240, height: 150))
    }

    func testResizeFlipsWhenCrossingOppositeCorner() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let model = SelectionModel(bounds: bounds, selection: selection)
        let rect = model.resized(.topLeft, to: CGPoint(x: 500, y: 500))
        XCTAssertEqual(rect, CGRect(x: 300, y: 200, width: 200, height: 300))
    }

    func testMoveIsClamped() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let model = SelectionModel(bounds: bounds, selection: selection)
        XCTAssertEqual(model.moved(selection, by: CGSize(width: -500, height: 0)).origin.x, 0)
        XCTAssertEqual(model.moved(selection, by: CGSize(width: 0, height: 800)).origin.y,
                       bounds.maxY - selection.height)
    }

    func testHandlePositions() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let handles = model.handles(for: selection)
        XCTAssertEqual(handles.count, 8)
        XCTAssertEqual(handles[0].1, CGPoint(x: 100, y: 100))
        XCTAssertEqual(handles[4].1, CGPoint(x: 300, y: 200))
    }
}
