import AppKit
import CoreGraphics
import Foundation

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// 11 × 2 调色板：第一行饱和色，第二行粉彩色。
    public static let palette: [RGBAColor] = [
        RGBAColor(r: 0.898, g: 0.224, b: 0.208), // 红（默认）
        RGBAColor(r: 0.984, g: 0.549, b: 0.0),   // 橙
        RGBAColor(r: 0.992, g: 0.847, b: 0.208), // 黄
        RGBAColor(r: 0.263, g: 0.627, b: 0.278), // 绿
        RGBAColor(r: 0.0, g: 0.675, b: 0.757),   // 青
        RGBAColor(r: 0.118, g: 0.533, b: 0.898), // 蓝
        RGBAColor(r: 0.557, g: 0.141, b: 0.667), // 紫
        RGBAColor(r: 0.847, g: 0.106, b: 0.376), // 粉
        RGBAColor(r: 0.427, g: 0.298, b: 0.255), // 棕
        RGBAColor(r: 0.459, g: 0.459, b: 0.459), // 灰
        RGBAColor(r: 0.129, g: 0.129, b: 0.129), // 黑

        RGBAColor(r: 0.937, g: 0.604, b: 0.604),
        RGBAColor(r: 1.0, g: 0.800, b: 0.502),
        RGBAColor(r: 1.0, g: 0.961, b: 0.616),
        RGBAColor(r: 0.647, g: 0.839, b: 0.655),
        RGBAColor(r: 0.502, g: 0.871, b: 0.918),
        RGBAColor(r: 0.565, g: 0.792, b: 0.976),
        RGBAColor(r: 0.808, g: 0.576, b: 0.847),
        RGBAColor(r: 0.957, g: 0.561, b: 0.694),
        RGBAColor(r: 0.737, g: 0.667, b: 0.643),
        RGBAColor(r: 0.878, g: 0.878, b: 0.878),
        RGBAColor(r: 1.0, g: 1.0, b: 1.0)
    ]
}

public enum ToolKind: String, Codable, CaseIterable, Sendable {
    case rectangle
    case ellipse
    case arrow
    case pen
    case marker
    case mosaic
    case text
    case eraser

    public var title: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "铅笔"
        case .marker: return "马克笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        case .eraser: return "橡皮"
        }
    }

    /// 默认线宽：普通 3、马克笔 24、马赛克/橡皮 28。
    public var defaultWidth: CGFloat {
        switch self {
        case .marker: return 24
        case .mosaic, .eraser: return 28
        default: return 3
        }
    }

    public var supportsFill: Bool { self == .rectangle || self == .ellipse }
    public var supportsBrushMode: Bool { self == .marker || self == .mosaic || self == .eraser }
    public var supportsOpacity: Bool { self == .marker }
    public var supportsBlockSize: Bool { self == .mosaic }
    public var supportsArrowStyle: Bool { self == .arrow }
    public var supportsWidth: Bool { self != .text }
}

public enum ArrowStyle: String, Codable, CaseIterable, Sendable {
    case solid
    case open
    case outline
    case double
    case line
    case taperedSolid
    case taperedOutline

    public var title: String {
        switch self {
        case .solid: return "实心箭头"
        case .open: return "开口箭头"
        case .outline: return "描边箭头"
        case .double: return "双向箭头"
        case .line: return "直线"
        case .taperedSolid: return "锥形实心"
        case .taperedOutline: return "锥形描边"
        }
    }
}

/// 一个标注对象。所有坐标都是"全局模型坐标"（左上原点，单位 point）。
public struct Shape: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case rectangle, ellipse, arrow, pen, marker, mosaic, eraser, text
    }

    public var kind: Kind
    public var color: RGBAColor
    public var lineWidth: CGFloat
    public var filled: Bool = false
    public var opacity: CGFloat = 1
    public var arrowStyle: ArrowStyle = .solid
    public var points: [CGPoint] = []
    public var start: CGPoint = .zero
    public var end: CGPoint = .zero
    public var rect: CGRect = .zero
    public var rectangular: Bool = false
    public var blockSize: CGFloat = 12
    public var text: String = ""
    public var fontSize: CGFloat = 16
    public var fontFamily: String = "PingFang SC"
    public var bold: Bool = false
    public var italic: Bool = false
    public var textOrigin: CGPoint = .zero

    public init(kind: Kind, color: RGBAColor = RGBAColor.palette[0], lineWidth: CGFloat = 3) {
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    public static func make(tool: ToolKind, at point: CGPoint, color: RGBAColor, lineWidth: CGFloat, fontSize: CGFloat) -> Shape {
        var shape: Shape
        switch tool {
        case .rectangle: shape = .init(kind: .rectangle, color: color, lineWidth: lineWidth)
        case .ellipse: shape = .init(kind: .ellipse, color: color, lineWidth: lineWidth)
        case .arrow: shape = .init(kind: .arrow, color: color, lineWidth: lineWidth)
        case .pen: shape = .init(kind: .pen, color: color, lineWidth: lineWidth)
        case .marker: shape = .init(kind: .marker, color: color, lineWidth: lineWidth)
        case .mosaic: shape = .init(kind: .mosaic, color: color, lineWidth: lineWidth)
        case .eraser: shape = .init(kind: .eraser, color: color, lineWidth: lineWidth)
        case .text: shape = .init(kind: .text, color: color, lineWidth: lineWidth)
        }
        shape.start = point
        shape.end = point
        shape.textOrigin = point
        shape.points = [point]
        shape.rect = CGRect(origin: point, size: .zero)
        if tool == .text { shape.fontSize = fontSize }
        return shape
    }

    /// 拖拽过程中的实时几何更新。
    public mutating func update(to point: CGPoint) {
        switch kind {
        case .rectangle, .ellipse, .arrow:
            end = point
            rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y))
        case .pen, .marker:
            if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 2 { return }
            points.append(point)
        case .mosaic, .eraser:
            if rectangular {
                end = point
                rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            } else if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 2 {
                return
            } else {
                points.append(point)
            }
        case .text:
            break
        }
    }

    public var isEmpty: Bool {
        switch kind {
        case .rectangle, .ellipse, .arrow, .mosaic:
            return rect.width < 2 && rect.height < 2
        case .pen, .marker, .eraser:
            return points.count < 2
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        switch kind {
        case .text:
            let rect = AnnotationMetrics.textBounds(text: text, family: fontFamily,
                                                    size: fontSize, bold: bold, italic: italic,
                                                    origin: textOrigin)
            return rect.insetBy(dx: -4, dy: -4).contains(point)
        default:
            return false
        }
    }
}

/// 文字排版测量，渲染和命中测试共用。
public enum AnnotationMetrics {
    public static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var font = NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            font = NSFontManager.shared.convert(font, toHaveTrait: traits) ?? font
        }
        return font
    }

    public static func attributes(family: String, size: CGFloat, bold: Bool, italic: Bool, color: RGBAColor) -> [NSAttributedString.Key: Any] {
        let font = font(family: family, size: size, bold: bold, italic: italic)
        return [.font: font, .foregroundColor: NSColor(cgColor: color.cgColor) ?? .red]
    }

    public static func textBounds(text: String, family: String, size: CGFloat,
                                  bold: Bool, italic: Bool, origin: CGPoint) -> CGRect {
        guard !text.isEmpty else { return CGRect(origin: origin, size: .zero) }
        let attributes = attributes(family: family, size: size, bold: bold, italic: italic,
                                    color: RGBAColor.palette[0])
        let size2 = (text as NSString).size(withAttributes: attributes)
        return CGRect(x: origin.x, y: origin.y, width: size2.width, height: size2.height)
    }
}
