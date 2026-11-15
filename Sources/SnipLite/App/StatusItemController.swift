import AppKit
import SnipLiteCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let settings = SettingsStore.shared
    private weak var historyItem: NSMenuItem?
    private weak var disableHotkeyItem: NSMenuItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "\(AppInfo.name) \(AppInfo.version)"
        }

        menu.autoenablesItems = false
        menu.delegate = self
        buildMenu()
        statusItem.menu = menu
    }

    // MARK: - 菜单

    private func buildMenu() {
        let settings = settings.settings

        addItem("截屏", shortcut: settings.captureHotkey, action: #selector(startCapture))
        addItem("截屏并自动复制", action: #selector(startCaptureWithCopy))
        addItem("自定义截屏…", action: #selector(startCustomCapture))
        menu.addItem(.separator())

        addItem("贴图 / 恢复贴图", shortcut: settings.pinHotkey, action: #selector(pinFromClipboard))
        addItem("隐藏 / 显示所有贴图", action: #selector(togglePins))
        addItem("切换到另一贴图分组", action: #selector(switchPinGroup))
        addItem("恢复最近关闭的贴图", action: #selector(restorePin))
        addItem("关闭全部贴图", action: #selector(closeAllPins))

        let history = addItem("截屏历史", enabled: true)
        history.submenu = NSMenu()
        historyItem = history

        addItem("清空截屏历史", action: #selector(clearHistory))
        menu.addItem(.separator())

        let disable = addItem("禁用快捷键", action: #selector(toggleHotkeys))
        disable.state = settings.hotkeysEnabled ? .off : .on
        disableHotkeyItem = disable
        addItem("文字识别", shortcut: settings.ocrHotkey, action: #selector(startOCR))
        addItem("二维码识别", shortcut: settings.qrHotkey, action: #selector(startQR))
        addItem("截图翻译", shortcut: settings.translationHotkey, action: #selector(startTranslation))
        menu.addItem(.separator())

        addItem("设置…", shortcut: .init(key: ",", modifiers: [.command]),
                action: #selector(showPreferences))
        addItem("关于 \(AppInfo.name)", action: #selector(showAbout))
        addItem("打开日志", action: #selector(openLog))
        menu.addItem(.separator())

        addItem("退出 \(AppInfo.name)", shortcut: .init(key: "Q", modifiers: [.command]),
                action: #selector(quit))
    }

    @discardableResult
    private func addItem(_ title: String,
                         shortcut: HotkeyBinding = .unset,
                         enabled: Bool = true,
                         action: Selector? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        item.isEnabled = enabled
        applyShortcut(shortcut, to: item)
        menu.addItem(item)
        return item
    }

    private func applyShortcut(_ binding: HotkeyBinding, to item: NSMenuItem) {
        guard let key = binding.key, !key.isEmpty else { return }
        item.keyEquivalent = key.lowercased()
        var flags: NSEvent.ModifierFlags = []
        for modifier in binding.modifiers {
            switch modifier {
            case .control: flags.insert(.control)
            case .option: flags.insert(.option)
            case .shift: flags.insert(.shift)
            case .command: flags.insert(.command)
            }
        }
        item.keyEquivalentModifierMask = flags
    }

    // MARK: - 动作

    @objc private func startCapture() {
        CaptureSession.start(mode: .capture)
    }

    @objc private func startCaptureWithCopy() {
        CaptureSession.start(mode: .capture, autoCopy: true)
    }

    @objc private func startCustomCapture() {
        Task { @MainActor in
            CustomRegionWindowController.shared.show(prefill: nil) { rect in
                CaptureSession.start(mode: .capture, preset: rect)
            }
        }
    }

    @objc private func pinHistoryItem(_ sender: NSMenuItem) {
        let items = CaptureHistory.shared.items
        guard sender.tag >= 0, sender.tag < items.count,
              let image = items[sender.tag].makeImage() else { return }
        Task { @MainActor in
            let mouse = NSEvent.mouseLocation
            PinController.shared.pin(image: image, topLeft: NSPoint(x: mouse.x - 40, y: mouse.y + 40))
        }
    }

    @objc private func clearHistory() {
        CaptureHistory.shared.clear()
        SettingsStore.shared.update { $0.recentRegions = [] }
        Toast.show("已清空截屏历史")
    }

    @objc private func toggleHotkeys() {
        SettingsStore.shared.update { $0.hotkeysEnabled.toggle() }
        disableHotkeyItem?.state = SettingsStore.shared.settings.hotkeysEnabled ? .off : .on
    }

    @objc private func startOCR() {
        CaptureSession.start(mode: .ocr)
    }

    @objc private func startQR() {
        CaptureSession.start(mode: .qr)
    }

    @objc private func startTranslation() {
        CaptureSession.start(mode: .translation)
    }

    @objc private func pinFromClipboard() {
        Task { @MainActor in PinController.shared.pasteFromClipboard() }
    }

    @objc private func togglePins() {
        Task { @MainActor in PinController.shared.toggleAll() }
    }

    @objc private func restorePin() {
        Task { @MainActor in _ = PinController.shared.restoreLast() }
    }

    @objc private func switchPinGroup() {
        Task { @MainActor in PinController.shared.switchGroup() }
    }

    @objc private func closeAllPins() {
        Task { @MainActor in PinController.shared.closeAll() }
    }

    @objc private func showPreferences() {
        Task { @MainActor in
            PreferencesWindowController.shared.show()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let screenRecording = Permissions.screenRecordingGranted ? "已授权" : "未授权"
        let accessibility = Permissions.accessibilityGranted ? "已授权" : "未授权"

        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) \(AppInfo.version)"
        alert.informativeText = """
        macOS 移植版 · 当前为 P0 骨架

        屏幕录制：\(screenRecording)
        辅助功能：\(accessibility)

        配置文件：\(AppPaths.settingsFile.path)
        """
        alert.addButton(withTitle: "屏幕录制设置…")
        alert.addButton(withTitle: "辅助功能设置…")
        alert.addButton(withTitle: "好")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Permissions.openScreenRecordingSettings()
        case .alertSecondButtonReturn:
            Permissions.openAccessibilitySettings()
        default:
            break
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logFile])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        AppLog.shared.write("打开状态栏菜单", level: .debug)
        rebuildHistoryMenu()
        disableHotkeyItem?.state = SettingsStore.shared.settings.hotkeysEnabled ? .off : .on
    }

    private func rebuildHistoryMenu() {
        guard let historyItem else { return }
        let submenu = NSMenu()
        let items = CaptureHistory.shared.items
        if items.isEmpty {
            let empty = NSMenuItem(title: "暂无截屏历史", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            for (index, item) in items.enumerated() {
                let title = "\(formatter.string(from: item.date))  \(Int(item.bounds.width)) × \(Int(item.bounds.height))"
                let entry = NSMenuItem(title: title, action: #selector(pinHistoryItem(_:)), keyEquivalent: "")
                entry.tag = index
                entry.target = self
                submenu.addItem(entry)
            }
        }
        historyItem.submenu = submenu
    }
}
