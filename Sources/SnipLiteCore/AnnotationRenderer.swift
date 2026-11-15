import AppKit
import CoreGraphics
import CoreText
import Foundation

public enum AnnotationRenderer {
    /// 把所有标注渲染成一张与虚拟屏幕等大的透明图层。
    public static func renderLayer(shapes: [Shape], geometry: ScreenGeometry, sampler: BitmapSampler?) -> CGImage? {
        let scale = geometry.canvasScale
        let width = Int((geometry.union.width * scale).rounded(.up))
        let height = Int((geometry.union.height * scale).rounded(.up))
        guard width > 0, height > 0, !shapes.isEmpty,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        for shape in shapes {
            draw(shape, in: context, scale: scale, sampler: sampler)
        }
        return context.makeImage()
    }

    public static func draw(_ shape: Shape, in context: CGContext, scale: CGFloat, sampler: BitmapSampler?) {
        switch shape.kind {
        case .rectangle, .ellipse:
            drawRectLike(shape, in: context)
        case .pen, .marker:
            drawStroke(shape, in: context)
        case .arrow:
            drawArrow(shape, in: context)
        case .mosaic:
            drawMosaic(shape, in: context, scale: scale, sampler: sampler)
        case .eraser:
            drawEraser(shape, in: context)
        case .text:
            drawText(shape, in: context)
        }
    }

    // MARK: - 各形状

    private static func drawRectLike(_ shape: Shape, in context: CGContext) {
        guard shape.rect.width > 0 || shape.rect.height > 0 else { return }
        let path = shape.kind == .rectangle
            ? CGPath(rect: shape.rect, transform: nil)
            : CGPath(ellipseIn: shape.rect, transform: nil)
        context.addPath(path)
        if shape.filled {
            context.setFillColor(shape.color.cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(shape.color.cgColor)
            context.setLineWidth(shape.lineWidth)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }

    private static func drawStroke(_ shape: Shape, in context: CGContext) {
        guard shape.points.count > 1 else { return }
        context.beginPath()
        context.move(to: shape.points[0])
        for point in shape.points.dropFirst() {
            context.addLine(to: point)
        }
        var color = shape.color
        if shape.kind == .marker { color.a *= shape.opacity }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(shape.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    private static func drawArrow(_ shape: Shape, in context: CGContext) {
        let start = shape.start
        let end = shape.end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let angle = atan2(dy, dx)
        let headLength = max(10, min(28, length * 0.28)) + shape.lineWidth * 1.5
        let headWidth = headLength * 0.62

        context.setStrokeColor(shape.color.cgColor)
        context.setFillColor(shape.color.cgColor)
        context.setLineWidth(shape.lineWidth)
        context.setLineCap(.round)

        switch shape.arrowStyle {
        case .line:
            strokeLine(context, from: start, to: end)
        case .open:
            strokeLine(context, from: start, to: end)
            let back = headLength * 0.9
            let left = CGPoint(x: end.x - cos(angle - .pi / 7) * back,
                               y: end.y - sin(angle - .pi / 7) * back)
            let right = CGPoint(x: end.x - cos(angle + .pi / 7) * back,
                                y: end.y - sin(angle + .pi / 7) * back)
            strokeLine(context, from: end, to: left)
            strokeLine(context, from: end, to: right)
        case .double:
            let unitX = cos(angle), unitY = sin(angle)
            strokeLine(context,
                       from: CGPoint(x: start.x + unitX * headLength * 0.7, y: start.y + unitY * headLength * 0.7),
                       to: CGPoint(x: end.x - unitX * headLength * 0.7, y: end.y - unitY * headLength * 0.7))
            fillTriangle(context, tip: end, angle: angle, length: headLength, width: headWidth)
            fillTriangle(context, tip: start, angle: angle + .pi, length: headLength, width: headWidth)
        case .taperedSolid, .taperedOutline:
            let base = CGPoint(x: end.x - cos(angle) * headLength, y: end.y - sin(angle) * headLength)
            let neck = CGPoint(x: end.x - cos(angle) * headLength * 0.45, y: end.y - sin(angle) * headLength * 0.45)
            let perpX = -sin(angle), perpY = cos(angle)
            let path = CGMutablePath()
            path.move(to: end)
            path.addLine(to: CGPoint(x: neck.x + perpX * headWidth * 0.12, y: neck.y + perpY * headWidth * 0.12))
            path.addLine(to: CGPoint(x: base.x + perpX * headWidth / 2, y: base.y + perpY * headWidth / 2))
            path.addLine(to: CGPoint(x: base.x - perpX * headWidth / 2, y: base.y - perpY * headWidth / 2))
            path.addLine(to: CGPoint(x: neck.x - perpX * headWidth * 0.12, y: neck.y - perpY * headWidth * 0.12))
            path.closeSubpath()
            if shape.arrowStyle == .taperedSolid {
                context.addPath(path)
                context.fillPath()
            } else {
                context.addPath(path)
                context.strokePath()
            }
            strokeLine(context, from: start, to: neck)
        default: // solid / outline
            let unitX = cos(angle), unitY = sin(angle)
            strokeLine(context,
                       from: start,
                       to: CGPoint(x: end.x - unitX * headLength * 0.75, y: end.y - unitY * headLength * 0.75))
            if shape.arrowStyle == .outline {
                let path = trianglePath(tip: end, angle: angle, length: headLength, width: headWidth)
                context.addPath(path)
                context.strokePath()
                context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
            } else {
                fillTriangle(context, tip: end, angle: angle, length: headLength, width: headWidth)
            }
        }
    }

    private static func strokeLine(_ context: CGContext, from: CGPoint, to: CGPoint) {
        context.beginPath()
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }

    private static func trianglePath(tip: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) -> CGPath {
        let back = CGPoint(x: tip.x - cos(angle) * length, y: tip.y - sin(angle) * length)
        let perpX = -sin(angle), perpY = cos(angle)
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: back.x + perpX * width / 2, y: back.y + perpY * width / 2))
        path.addLine(to: CGPoint(x: back.x - perpX * width / 2, y: back.y - perpY * width / 2))
        path.closeSubpath()
        return path
    }

    private static func fillTriangle(_ context: CGContext, tip: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) {
        context.addPath(trianglePath(tip: tip, angle: angle, length: length, width: width))
        context.fillPath()
    }

    private static func drawMosaic(_ shape: Shape, in context: CGContext, scale: CGFloat, sampler: BitmapSampler?) {
        guard let sampler else { return }
        let block = max(2, (shape.blockSize * scale).rounded())
        var area: CGRect
        var outline: CGPath?

        if shape.rectangular {
            area = CGRect(x: shape.rect.minX * scale, y: shape.rect.minY * scale,
                          width: shape.rect.width * scale, height: shape.rect.height * scale)
        } else {
            guard shape.points.count > 1 else { return }
            let path = CGMutablePath()
            path.move(to: shape.points[0])
            for point in shape.points.dropFirst() { path.addLine(to: point) }
            outline = path.copy(strokingWithWidth: shape.lineWidth,
                                lineCap: .round, lineJoin: .round, miterLimit: 10)
            let bounds = outline!.boundingBoxOfPath
            area = CGRect(x: bounds.minX * scale, y: bounds.minY * scale,
                          width: bounds.width * scale, height: bounds.height * scale)
        }
        guard area.width > 0, area.height > 0 else { return }

        let startX = (area.minX / block).rounded(.down) * block
        let startY = (area.minY / block).rounded(.down) * block

        var y = startY
        while y < area.maxY {
            var x = startX
            while x < area.maxX {
                let blockRect = CGRect(x: x, y: y, width: block, height: block)
                if let outline {
                    let center = CGPoint(x: (x + block / 2) / scale, y: (y + block / 2) / scale)
                    if !outline.contains(center) {
                        x += block
                        continue
                    }
                }
                let color = sampler.averageColor(in: blockRect)
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: x / scale, y: y / scale,
                                    width: block / scale, height: block / scale))
                x += block
            }
            y += block
        }
    }

    private static func drawEraser(_ shape: Shape, in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(shape.lineWidth)
        if shape.rectangular {
            context.fill(shape.rect)
        } else if shape.points.count > 1 {
            context.beginPath()
            context.move(to: shape.points[0])
            for point in shape.points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawText(_ shape: Shape, in context: CGContext) {
        guard !shape.text.isEmpty else { return }
        let attributes = AnnotationMetrics.attributes(family: shape.fontFamily,
                                                      size: shape.fontSize,
                                                      bold: shape.bold,
                                                      italic: shape.italic,
                                                      color: shape.color)
        let attributed = NSAttributedString(string: shape.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, nil, nil)

        context.saveGState()
        context.translateBy(x: shape.textOrigin.x, y: shape.textOrigin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

public enum ImageComposer {
    /// 按顺序叠加图层（图层尺寸与 base 相同）。
    public static func overlay(base: CGImage, layers: [CGImage]) -> CGImage? {
        guard !layers.isEmpty else { return base }
        let width = base.width
        let height = base.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: target)
        for layer in layers {
            context.draw(layer, in: target)
        }
        return context.makeImage()
    }

    /// 把冻结截图和标注层按 crop（画布像素坐标）合成。
    public static func composite(base: CGImage, layer: CGImage?, crop: CGRect) -> CGImage? {
        let rect = crop.integral
        guard rect.width >= 1, rect.height >= 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: Int(rect.width),
                                      height: Int(rect.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let target = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        if let cropBase = base.cropping(to: rect) {
            context.draw(cropBase, in: target)
        }
        if let layer, let cropLayer = layer.cropping(to: rect) {
            context.draw(cropLayer, in: target)
        }
        return context.makeImage()
    }
}
