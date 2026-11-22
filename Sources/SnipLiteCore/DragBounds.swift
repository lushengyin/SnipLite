import CoreGraphics

/// 悬浮窗口拖动时的边界约束。
/// 允许窗口部分移出屏幕，但始终保留一段可见边缘，方便随时拖回屏幕内。
public enum DragBounds {
    /// 默认保留的可见边缘宽度（point）。
    public static let minimumVisibleEdge: CGFloat = 24

    /// 把窗口原点限制在 `screen` 允许的范围内：
    /// 窗口可以越过任意一条边，但至少要有 `visibleEdge` 宽的边缘留在屏幕内。
    /// 窗口尺寸小于 `visibleEdge` 时，按窗口自身尺寸计算，即必须完整可见。
    public static func clamp(origin: CGPoint,
                             size: CGSize,
                             within screen: CGRect,
                             visibleEdge: CGFloat = minimumVisibleEdge) -> CGPoint {
        let edgeX = min(max(0, visibleEdge), size.width)
        let edgeY = min(max(0, visibleEdge), size.height)
        return CGPoint(
            x: min(max(origin.x, screen.minX - size.width + edgeX), screen.maxX - edgeX),
            y: min(max(origin.y, screen.minY - size.height + edgeY), screen.maxY - edgeY)
        )
    }
}
