import CoreGraphics
import Foundation

public enum SelectionHandle: Int, CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

/// 选区几何运算。纯函数，方便单测；视图层只负责把事件坐标喂进来。
public struct SelectionModel: Sendable {
    public var bounds: CGRect
    public var selection: CGRect?
    /// 控制点命中半径（点）。
    public var handleRadius: CGFloat

    public init(bounds: CGRect, selection: CGRect? = nil, handleRadius: CGFloat = 8) {
        self.bounds = bounds
        self.selection = selection
        self.handleRadius = handleRadius
    }

    public func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(a.x - b.x), height: abs(a.y - b.y))
        return clamped(rect)
    }

    public func clamped(_ rect: CGRect) -> CGRect {
        rect.intersection(bounds)
    }

    public func isDraggingNewSelection(anchor: CGPoint, current: CGPoint) -> Bool {
        normalized(anchor, current).width < 3 && normalized(anchor, current).height < 3
    }

    public func handles(for selection: CGRect) -> [(SelectionHandle, CGPoint)] {
        let minX = selection.minX, maxX = selection.maxX
        let minY = selection.minY, maxY = selection.maxY
        let midX = selection.midX, midY = selection.midY
        return [
            (.topLeft, CGPoint(x: minX, y: minY)),
            (.top, CGPoint(x: midX, y: minY)),
            (.topRight, CGPoint(x: maxX, y: minY)),
            (.right, CGPoint(x: maxX, y: midY)),
            (.bottomRight, CGPoint(x: maxX, y: maxY)),
            (.bottom, CGPoint(x: midX, y: maxY)),
            (.bottomLeft, CGPoint(x: minX, y: maxY)),
            (.left, CGPoint(x: minX, y: midY))
        ]
    }

    public func handle(at point: CGPoint) -> SelectionHandle? {
        guard let selection, selection.width >= 1, selection.height >= 1 else { return nil }
        var best: SelectionHandle?
        var bestDistance = handleRadius
        for (handle, center) in handles(for: selection) {
            let distance = hypot(center.x - point.x, center.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                best = handle
            }
        }
        return best
    }

    public func resized(_ handle: SelectionHandle, to point: CGPoint) -> CGRect {
        guard let selection else { return .zero }
        let p = clampedPoint(point)
        var minX = selection.minX, minY = selection.minY
        var maxX = selection.maxX, maxY = selection.maxY

        switch handle {
        case .topLeft:
            minX = p.x; minY = p.y
        case .top:
            minY = p.y
        case .topRight:
            maxX = p.x; minY = p.y
        case .right:
            maxX = p.x
        case .bottomRight:
            maxX = p.x; maxY = p.y
        case .bottom:
            maxY = p.y
        case .bottomLeft:
            minX = p.x; maxY = p.y
        case .left:
            minX = p.x
        }

        // 拖过头时按边翻转，和常见选区工具一致，不产生 0 宽高。
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY)).integration
    }

    public func moved(_ selection: CGRect, by delta: CGSize) -> CGRect {
        var rect = selection.offsetBy(dx: delta.width, dy: delta.height)
        if rect.minX < bounds.minX { rect.origin.x = bounds.minX }
        if rect.minY < bounds.minY { rect.origin.y = bounds.minY }
        if rect.maxX > bounds.maxX { rect.origin.x = bounds.maxX - rect.width }
        if rect.maxY > bounds.maxY { rect.origin.y = bounds.maxY - rect.height }
        return rect
    }

    public func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}

private extension CGRect {
    /// 选区对齐到整点，避免缩放控制点后出现半像素宽高。
    var integration: CGRect {
        CGRect(x: minX.rounded(.down), y: minY.rounded(.down),
               width: width.rounded(), height: height.rounded())
    }
}
