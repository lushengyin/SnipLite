import AppKit
import CoreGraphics
import CoreText
import Foundation

public struct TranslationBlock: Equatable, Sendable {
    public var text: String
    /// 相对裁剪区域的像素坐标。
    public var bounds: CGRect

    public init(text: String, bounds: CGRect) {
        self.text = text
        self.bounds = bounds
    }
}

/// 把 OCR 的逐行结果合并成段落块：行距接近且左边界对齐的相邻行合并。
public enum TranslationOverlayBuilder {
    public static func blocks(from document: OcrDocument) -> [TranslationBlock] {
        guard !document.isEmpty else { return [] }

        var lines: [(text: String, bounds: CGRect)] = []
        var currentText = ""
        var currentBounds: CGRect = .null

        for character in document.characters {
            if character.prefix.contains("\n"), !currentText.isEmpty {
                lines.append((currentText, currentBounds))
                currentText = ""
                currentBounds = .null
            }
            currentText += character.text
            currentBounds = currentBounds.isNull ? character.bounds : currentBounds.union(character.bounds)
        }
        if !currentText.isEmpty { lines.append((currentText, currentBounds)) }
        guard !lines.isEmpty else { return [] }

        var blocks: [TranslationBlock] = []
        var blockText = lines[0].text
        var blockBounds = lines[0].bounds

        for line in lines.dropFirst() {
            let lineHeight = max(blockBounds.height, 1)
            let gap = line.bounds.minY - blockBounds.maxY
            let leftDelta = abs(line.bounds.minX - blockBounds.minX)
            let mergeable = gap >= -0.2 * lineHeight && gap <= 0.8 * lineHeight
                && leftDelta <= 0.65 * lineHeight
            if mergeable {
                blockText += line.text
                blockBounds = blockBounds.union(line.bounds)
            } else {
                blocks.append(TranslationBlock(text: blockText, bounds: blockBounds))
                blockText = line.text
                blockBounds = line.bounds
            }
        }
        blocks.append(TranslationBlock(text: blockText, bounds: blockBounds))
        return blocks
    }
}

/// 把译文画回原位置：采样背景色覆盖原文，再画自适应字号的译文。
public enum TranslationOverlayRenderer {
    public static func render(base: CGImage,
                              blocks: [TranslationBlock],
                              translations: [String],
                              sampler: BitmapSampler?) -> CGImage? {
        guard blocks.count == translations.count, !blocks.isEmpty else { return nil }
        let width = base.width
        let height = base.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        for (block, translation) in zip(blocks, translations) {
            let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != block.text.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }

            let area = block.bounds.integral
            guard area.width >= 2, area.height >= 2 else { continue }
            let padding = min(max(0.18 * area.height, 2), 8)
            let cover = area.insetBy(dx: -padding, dy: -padding)
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard cover.width > 1, cover.height > 1 else { continue }

            let background = sampler?.averageColor(in: cover) ?? RGBAColor(r: 1, g: 1, b: 1)
            context.setFillColor(background.cgColor)
            context.fill(cover)

            let luminance = 0.299 * background.r + 0.587 * background.g + 0.114 * background.b
            let foreground = luminance > 0.55
                ? RGBAColor(r: 0.1, g: 0.1, b: 0.1)
                : RGBAColor(r: 1, g: 1, b: 1)

            let maxSize = min(max(area.height, 6), 96)
            let fontSize = fitSize(text: trimmed, bounds: area, maxSize: maxSize)
            draw(text: trimmed, at: area.origin, fontSize: fontSize, color: foreground, in: context)
        }
        return context.makeImage()
    }

    private static func fitSize(text: String, bounds: CGRect, maxSize: CGFloat) -> CGFloat {
        var low: CGFloat = 4
        var high: CGFloat = maxSize
        for _ in 0..<8 {
            let mid = (low + high) / 2
            let size = measure(text: text, fontSize: mid)
            if size.width <= bounds.width && size.height <= bounds.height {
                low = mid
            } else {
                high = mid
            }
        }
        return max(4, low)
    }

    private static func measure(text: String, fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes)
    }

    private static func draw(text: String, at origin: CGPoint, fontSize: CGFloat,
                             color: RGBAColor, in context: CGContext) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color.cgColor) ?? .white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, nil, nil)

        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
