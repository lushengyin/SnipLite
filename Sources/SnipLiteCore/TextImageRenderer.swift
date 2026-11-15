import AppKit
import CoreGraphics
import CoreText
import Foundation

/// 把剪贴板文字渲染成图片，供贴图使用。
public enum TextImageRenderer {
    public static func render(text: String,
                              fontName: String = "",
                              fontSize: CGFloat = 13,
                              background: RGBAColor = RGBAColor(r: 1, g: 1, b: 1),
                              foreground: RGBAColor = RGBAColor(r: 0.1, g: 0.1, b: 0.1),
                              margin: CGFloat = 15,
                              maxWidth: CGFloat = 900) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let font = fontName.isEmpty
            ? NSFont.systemFont(ofSize: fontSize)
            : (NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize))
        let attributed = NSAttributedString(string: trimmed, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: foreground.cgColor) ?? .black
        ])

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let maxTextWidth = max(20, maxWidth - margin * 2)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            nil
        )

        let width = Int((fit.width + margin * 2).rounded(.up))
        let height = Int((fit.height + margin * 2).rounded(.up))
        guard width > 0, height > 0, width <= 12000, height <= 30000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let path = CGPath(rect: CGRect(x: margin, y: margin,
                                       width: maxTextWidth, height: fit.height + 4),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        return context.makeImage()
    }
}
