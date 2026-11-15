import AppKit
import SnipLiteCore

/// 自定义截屏区域：输入宽高后直接进入截图。
@MainActor
final class CustomRegionWindowController: NSWindowController {
    static let shared = CustomRegionWindowController()

    private var xField: NSTextField!
    private var yField: NSTextField!
    private var widthField: NSTextField!
    private var heightField: NSTextField!
    private var onConfirm: ((CGRect) -> Void)?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 190),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "自定义截屏"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(prefill: CGRect?, onConfirm: @escaping (CGRect) -> Void) {
        let region = prefill ?? SettingsStore.shared.settings.recentRegions.first?.rect ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        xField.integerValue = Int(region.minX)
        yField.integerValue = Int(region.minY)
        widthField.integerValue = Int(region.width)
        heightField.integerValue = Int(region.height)
        self.onConfirm = onConfirm
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(widthField)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        func label(_ text: String, _ y: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: 20, y: y, width: 80, height: 20)
            content.addSubview(field)
            return field
        }

        func field(_ y: CGFloat) -> NSTextField {
            let input = NSTextField(frame: NSRect(x: 110, y: y - 3, width: 200, height: 24))
            content.addSubview(input)
            return input
        }

        _ = label("X", 140)
        xField = field(140)
        _ = label("Y", 110)
        yField = field(110)
        _ = label("宽", 80)
        widthField = field(80)
        _ = label("高", 50)
        heightField = field(50)

        let suggest = NSButton(title: "用上次区域", target: self, action: #selector(fillLastRegion))
        suggest.frame = NSRect(x: 20, y: 12, width: 110, height: 26)
        content.addSubview(suggest)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 160, y: 12, width: 80, height: 26)
        content.addSubview(cancel)

        let confirm = NSButton(title: "开始截屏", target: self, action: #selector(confirm))
        confirm.keyEquivalent = "\r"
        confirm.frame = NSRect(x: 240, y: 12, width: 90, height: 26)
        content.addSubview(confirm)
    }

    @objc private func fillLastRegion() {
        guard let region = SettingsStore.shared.settings.recentRegions.first else { return }
        xField.integerValue = Int(region.rect.minX)
        yField.integerValue = Int(region.rect.minY)
        widthField.integerValue = Int(region.rect.width)
        heightField.integerValue = Int(region.rect.height)
    }

    @objc private func cancel() {
        window?.orderOut(nil)
        onConfirm = nil
    }

    @objc private func confirm() {
        let rect = CGRect(x: xField.integerValue, y: yField.integerValue,
                          width: max(1, widthField.integerValue),
                          height: max(1, heightField.integerValue))
        let handler = onConfirm
        window?.orderOut(nil)
        onConfirm = nil
        handler?(rect)
    }
}
