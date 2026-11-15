import CoreGraphics
import Foundation

public struct RecognizedCharacter: Equatable, Sendable {
    public var text: String
    public var bounds: CGRect
    /// 插在该字符前面的换行或空格。
    public var prefix: String

    public init(text: String, bounds: CGRect, prefix: String = "") {
        self.text = text
        self.bounds = bounds
        self.prefix = prefix
    }
}

/// OCR 结果：行框 + 字符框 + 前缀。
/// 坐标是"相对选区裁剪区域"的 point（左上原点）。
public struct OcrDocument: Equatable, Sendable {
    public let characters: [RecognizedCharacter]
    public let lineBounds: [CGRect]

    public init(characters: [RecognizedCharacter], lineBounds: [CGRect] = []) {
        self.characters = characters
        self.lineBounds = lineBounds
    }

    public static let empty = OcrDocument(characters: [])

    public var isEmpty: Bool { characters.isEmpty }

    public var text: String {
        characters.reduce(into: "") { result, character in
            result += character.prefix + character.text
        }
    }

    public func getText(from a: Int, to b: Int) -> String {
        guard !characters.isEmpty else { return "" }
        let start = max(0, min(min(a, b), characters.count - 1))
        let end = max(0, min(max(a, b), characters.count - 1))
        guard start <= end else { return "" }
        return characters[start...end].reduce(into: "") { result, character in
            result += character.prefix + character.text
        }
    }

    /// 命中字符索引；`nearest` 为真时总是返回最近的字符。
    public func hitTest(_ point: CGPoint, nearest: Bool, tolerance: CGFloat) -> Int {
        var bestIndex = -1
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, character) in characters.enumerated() {
            if character.bounds.contains(point) { return index }
            let rect = character.bounds
            let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
            let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        guard bestIndex >= 0 else { return -1 }
        if nearest { return bestIndex }
        return bestDistance <= tolerance * tolerance ? bestIndex : -1
    }
}
