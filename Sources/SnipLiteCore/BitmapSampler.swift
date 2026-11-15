import CoreGraphics
import Foundation

/// 冻结截图的像素采样器，马赛克专用。
/// 坐标是"左上原点的画布像素"，内部缓存 RGBA8，采样时自己处理上下翻转。
public final class BitmapSampler {
    public let width: Int
    public let height: Int
    private let pixels: [UInt8]
    private let bytesPerRow: Int

    public init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        let bpr = w * 4
        width = w
        height = h
        bytesPerRow = bpr
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: bpr * h)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: w,
                                          height: h,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bpr,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        pixels = buffer
    }

    /// 单个像素的颜色（左上原点像素坐标）。
    public func color(at point: CGPoint) -> RGBAColor? {
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = (height - 1 - y) * bytesPerRow + x * 4
        let r = Double(pixels[offset]) / 255
        let g = Double(pixels[offset + 1]) / 255
        let b = Double(pixels[offset + 2]) / 255
        let a = Double(pixels[offset + 3]) / 255
        return RGBAColor(r: r, g: g, b: b, a: a)
    }

    /// 取一块区域的平均色（左上原点像素坐标）。
    public func averageColor(in rect: CGRect) -> RGBAColor {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard maxX > minX, maxY > minY else { return RGBAColor(r: 0, g: 0, b: 0) }

        var r = 0, g = 0, b = 0, count = 0
        var y = minY
        while y < maxY {
            let row = (height - 1 - y) * bytesPerRow
            var x = minX
            while x < maxX {
                let offset = row + x * 4
                r += Int(pixels[offset])
                g += Int(pixels[offset + 1])
                b += Int(pixels[offset + 2])
                count += 1
                x += 1
            }
            y += 1
        }
        guard count > 0 else { return RGBAColor(r: 0, g: 0, b: 0) }
        return RGBAColor(r: Double(r) / Double(count) / 255,
                         g: Double(g) / Double(count) / 255,
                         b: Double(b) / Double(count) / 255)
    }
}
