import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 会话内截图历史（内存，不落盘）。
/// 存 PNG 编码后的数据而不是解压后的位图：一张 4K 截图原始位图约 33 MB，
/// 编码后通常只有几 MB，需要贴图时再解码。
public final class CaptureHistory {
    public static let shared = CaptureHistory()

    public struct Item {
        public let data: Data
        public let bounds: CGRect
        public let date: Date

        /// 按需解码，调用方用完即释放。
        public func makeImage() -> CGImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }

    public private(set) var items: [Item] = []

    /// 压缩后总字节上限，超出时从最旧的开始淘汰。
    private let byteLimit = 32 * 1024 * 1024

    private init() {}

    public func add(image: CGImage, bounds: CGRect) {
        let limit = SettingsStore.shared.settings.historyImageLimit
        guard limit > 0 else {
            items.removeAll()
            return
        }
        guard let data = Self.encodePNG(image) else { return }
        items.insert(Item(data: data, bounds: bounds, date: Date()), at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        var total = items.reduce(0) { $0 + $1.data.count }
        while items.count > 1, total > byteLimit {
            total -= items.removeLast().data.count
        }
    }

    public func clear() {
        items.removeAll()
    }

    public var latest: Item? { items.first }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}
