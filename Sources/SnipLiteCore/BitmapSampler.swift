import CoreGraphics
import Foundation

/// 冻结截图的像素采样器，马赛克与取色专用。
/// 坐标是"左上原点的画布像素"。
/// 直接读 CGImage 的像素数据，不再复制整幅位图（4K 双屏约 65 MB）。
public final class BitmapSampler {
    public let width: Int
    public let height: Int

    private let image: CGImage
    private let bytes: UnsafePointer<UInt8>?
    private let data: CFData?
    private let bytesPerRow: Int
    /// 像素格式是否是可直接读取的 8bpc RGBA（本应用的画布与合成结果都是）。
    private let directReadable: Bool

    public init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        width = w
        height = h
        image = cgImage
        data = cgImage.dataProvider?.data
        bytes = data.map { CFDataGetBytePtr($0) }
        bytesPerRow = cgImage.bytesPerRow
        let info = cgImage.bitmapInfo
        let alpha = CGImageAlphaInfo(rawValue: info.rawValue & ~CGBitmapInfo.byteOrderMask.rawValue)
        directReadable = cgImage.bitsPerComponent == 8
            && bytes != nil
            && bytesPerRow >= w * 4
            && (alpha == .premultipliedLast || alpha == .noneSkipLast)
    }

    /// 单个像素的颜色（左上原点像素坐标）。
    public func color(at point: CGPoint) -> RGBAColor? {
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        if directReadable, let bytes {
            let offset = y * bytesPerRow + x * 4
            return RGBAColor(r: Double(bytes[offset]) / 255,
                             g: Double(bytes[offset + 1]) / 255,
                             b: Double(bytes[offset + 2]) / 255,
                             a: Double(bytes[offset + 3]) / 255)
        }
        return drawSampledColor(in: CGRect(x: x, y: y, width: 1, height: 1))
    }

    /// 取一块区域的平均色（左上原点像素坐标）。
    public func averageColor(in rect: CGRect) -> RGBAColor {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard maxX > minX, maxY > minY else { return RGBAColor(r: 0, g: 0, b: 0) }

        guard directReadable, let bytes else {
            return drawSampledColor(in: CGRect(x: minX, y: minY,
                                               width: maxX - minX, height: maxY - minY))
                ?? RGBAColor(r: 0, g: 0, b: 0)
        }

        // 大块区域按步长抽样，避免逐像素扫描整屏。
        let area = (maxX - minX) * (maxY - minY)
        let step = max(1, Int((Double(area) / 4096).squareRoot().rounded(.up)))
        var r = 0, g = 0, b = 0, count = 0
        var y = minY
        while y < maxY {
            let row = y * bytesPerRow
            var x = minX
            while x < maxX {
                let offset = row + x * 4
                r += Int(bytes[offset])
                g += Int(bytes[offset + 1])
                b += Int(bytes[offset + 2])
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return RGBAColor(r: 0, g: 0, b: 0) }
        return RGBAColor(r: Double(r) / Double(count) / 255,
                         g: Double(g) / Double(count) / 255,
                         b: Double(b) / Double(count) / 255)
    }

    /// 兜底：把目标区域画进一张小画布再读平均色。只用于非预期像素格式。
    private func drawSampledColor(in rect: CGRect) -> RGBAColor? {
        let w = max(1, Int(rect.width))
        let h = max(1, Int(rect.height))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let source = image.cropping(to: CGRect(x: rect.minX, y: rect.minY,
                                                     width: CGFloat(w), height: CGFloat(h))) else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var r = 0, g = 0, b = 0
        var index = 0
        while index < buffer.count {
            r += Int(buffer[index])
            g += Int(buffer[index + 1])
            b += Int(buffer[index + 2])
            index += 4
        }
        let count = max(1, buffer.count / 4)
        return RGBAColor(r: Double(r) / Double(count) / 255,
                         g: Double(g) / Double(count) / 255,
                         b: Double(b) / Double(count) / 255)
    }
}
