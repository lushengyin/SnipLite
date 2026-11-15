import AppKit
import CoreGraphics

/// 会话内截图历史（内存，不落盘）。
public final class CaptureHistory {
    public static let shared = CaptureHistory()

    public struct Item {
        public let image: CGImage
        public let bounds: CGRect
        public let date: Date
    }

    public private(set) var items: [Item] = []

    private init() {}

    public func add(image: CGImage, bounds: CGRect) {
        let limit = SettingsStore.shared.settings.historyImageLimit
        guard limit > 0 else {
            items.removeAll()
            return
        }
        items.insert(Item(image: image, bounds: bounds, date: Date()), at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }

    public func clear() {
        items.removeAll()
    }

    public var latest: Item? { items.first }
}
