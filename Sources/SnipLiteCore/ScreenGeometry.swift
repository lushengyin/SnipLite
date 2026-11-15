import CoreGraphics
import Foundation

/// 一块屏幕的快照。
/// `frame` 使用"全局左上原点"的 point 坐标——模型层统一用这一套坐标，
/// 只在和 AppKit/Cocoa 打交道时转换。
public struct ScreenInfo: Equatable, Sendable {
    public let frame: CGRect
    public let scale: CGFloat
    public let displayID: UInt32

    public init(frame: CGRect, scale: CGFloat, displayID: UInt32) {
        self.frame = frame
        self.scale = scale
        self.displayID = displayID
    }
}

/// 抓屏时冻结的屏幕布局。之后所有坐标换算都基于它，不再实时读 NSScreen，
/// 避免截图中显示器变化或分辨率切换导致坐标漂移。
public struct ScreenGeometry: Equatable, Sendable {
    public let screens: [ScreenInfo]
    /// 所有屏幕并集，原点 (0,0)，左上原点坐标系。
    public let union: CGRect
    /// 用于合成虚拟画布的像素倍率：取所有屏幕里最大的 scale。
    public let canvasScale: CGFloat

    public init(cocoaFrames: [(frame: CGRect, scale: CGFloat, displayID: UInt32)]) {
        let cocoaUnion = cocoaFrames.reduce(CGRect.null) { $0.union($1.frame) }
        let reference = cocoaUnion.isNull ? .zero : cocoaUnion

        self.screens = cocoaFrames.map { entry in
            // Cocoa 是左下原点且 Y 向上；翻转成左上原点。
            let flipped = CGRect(
                x: entry.frame.minX - reference.minX,
                y: reference.maxY - entry.frame.maxY,
                width: entry.frame.width,
                height: entry.frame.height
            )
            return ScreenInfo(frame: flipped, scale: entry.scale, displayID: entry.displayID)
        }
        self.union = CGRect(origin: .zero, size: reference.size)
        self.canvasScale = max(1, cocoaFrames.map(\.scale).max() ?? 1)
        self.cocoaUnion = reference
    }

    private let cocoaUnion: CGRect

    /// Cocoa 全局点（左下原点）→ 模型坐标（左上原点）。
    public func toModel(_ cocoaPoint: CGPoint) -> CGPoint {
        CGPoint(x: cocoaPoint.x - cocoaUnion.minX, y: cocoaUnion.maxY - cocoaPoint.y)
    }

    /// 模型坐标 → Cocoa 全局点。
    public func toCocoa(_ modelPoint: CGPoint) -> CGPoint {
        CGPoint(x: modelPoint.x + cocoaUnion.minX, y: cocoaUnion.maxY - modelPoint.y)
    }

    /// 单块屏幕的 Cocoa 窗口坐标（左下原点）。
    public func cocoaFrame(for screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.frame.minX + cocoaUnion.minX,
               y: cocoaUnion.maxY - screen.frame.maxY,
               width: screen.frame.width,
               height: screen.frame.height)
    }

    public func screen(at modelPoint: CGPoint) -> ScreenInfo? {
        screens.first { $0.frame.contains(modelPoint) }
            ?? screens.max { a, b in
                a.frame.insetBy(dx: -1000, dy: -1000).distance(to: modelPoint)
                    > b.frame.insetBy(dx: -1000, dy: -1000).distance(to: modelPoint)
            }
    }

    /// 选区按画布倍率换算成像素尺寸（用于尺寸徽标和导出）。
    public func pixelSize(of rect: CGRect) -> CGSize {
        let screen = screen(at: CGPoint(x: rect.midX, y: rect.midY))
        let scale = screen?.scale ?? canvasScale
        return CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
    }

    /// 选区在画布像素坐标中的位置。
    public func canvasRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * canvasScale, y: rect.minY * canvasScale,
               width: rect.width * canvasScale, height: rect.height * canvasScale)
    }
}

private extension CGRect {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = max(max(minX - point.x, 0), point.x - maxX)
        let dy = max(max(minY - point.y, 0), point.y - maxY)
        return hypot(dx, dy)
    }
}
