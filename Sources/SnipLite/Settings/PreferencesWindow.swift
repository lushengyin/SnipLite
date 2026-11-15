import AppKit
import ServiceManagement
import SnipLiteCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var maskSlider: NSSlider!
    private var zoomStepper: NSStepper!
    private var zoomLabel: NSTextField!
    private var patternField: NSTextField!
    private var qualitySlider: NSSlider!
    private var logPopup: NSPopUpButton!
    private var pinMaxStepper: NSStepper!
    private var pinMaxLabel: NSTextField!
    private var azureKeyField: NSSecureTextField!
    private var azureRegionField: NSTextField!
    private var hotkeyFields: [(HotkeyBindingKey, HotkeyField)] = []
    private var duplicateLabel: NSTextField!

    private enum HotkeyBindingKey: String, CaseIterable {
        case capture, pin, ocr, qr, translation

        var title: String {
            switch self {
            case .capture: return "截图"
            case .pin: return "贴图 / 恢复贴图"
            case .ocr: return "文字识别"
            case .qr: return "二维码识别"
            case .translation: return "截图翻译"
            }
        }
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "SnipLite 首选项"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI

    private func buildUI() {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder

        tabView.addTabViewItem(tab(title: "常规", view: makeGeneralPage()))
        tabView.addTabViewItem(tab(title: "截屏", view: makeCapturePage()))
        tabView.addTabViewItem(tab(title: "贴图", view: makePinPage()))
        tabView.addTabViewItem(tab(title: "输出", view: makeOutputPage()))
        tabView.addTabViewItem(tab(title: "控制", view: makeControlPage()))
        tabView.addTabViewItem(tab(title: "关于", view: makeAboutPage()))

        guard let content = window?.contentView else { return }
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func page(_ rows: [NSView]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18)
        ])
        return container
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    // MARK: - 页

    private func makeGeneralPage() -> NSView {
        logPopup = NSPopUpButton()
        for level in LogLevel.allCases {
            logPopup.addItem(withTitle: level.title)
            logPopup.lastItem?.representedObject = level.rawValue
        }
        logPopup.target = self
        logPopup.action = #selector(logLevelChanged)

        let permissions = NSStackView(views: [
            NSButton(title: "屏幕录制设置…", target: self, action: #selector(openScreenPermission)),
            NSButton(title: "辅助功能设置…", target: self, action: #selector(openAccessibilityPermission))
        ])
        permissions.orientation = .horizontal
        permissions.spacing = 8

        azureKeyField = NSSecureTextField(string: "")
        azureKeyField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        azureRegionField = NSTextField(string: "")
        azureRegionField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let saveKey = NSButton(title: "保存微软翻译密钥", target: self, action: #selector(saveAzureKey))

        return page([
            row("日志级别", logPopup),
            row("开机启动", toggle(#selector(startAtLoginChanged))),
            row("显示操作提示", toggle(#selector(showToastChanged))),
            row("权限", permissions),
            row("微软翻译密钥", azureKeyField),
            row("微软翻译区域", azureRegionField),
            row("", saveKey),
            row("提示", NSTextField(labelWithString: "开机启动使用 SMAppService；微软密钥保存在系统钥匙串"))
        ])
    }

    private func makeCapturePage() -> NSView {
        maskSlider = NSSlider(value: 110, minValue: 0, maxValue: 200,
                              target: self, action: #selector(maskChanged))
        maskSlider.isContinuous = false
        maskSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        zoomStepper = NSStepper()
        zoomStepper.minValue = 2
        zoomStepper.maxValue = 16
        zoomStepper.target = self
        zoomStepper.action = #selector(zoomChanged)
        zoomLabel = NSTextField(labelWithString: "6×")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let zoomRow = NSStackView(views: [zoomStepper, zoomLabel])
        zoomRow.orientation = .horizontal
        zoomRow.spacing = 8

        return page([
            row("遮罩不透明度", maskSlider),
            row("放大镜倍数", zoomRow),
            row("全屏十字线", toggle(#selector(showCrosshairChanged))),
            row("选区前自动放大镜", toggle(#selector(autoMagnifierChanged))),
            row("显示选区锚点", toggle(#selector(captureAnchorsChanged))),
            row("隐藏 1×1 提示", toggle(#selector(hideOnePixelHintChanged))),
            row("截图包含光标", toggle(#selector(captureCursorChanged))),
            row("自动检测窗口", toggle(#selector(detectWindowsChanged))),
            row("Esc 确认对话框", toggle(#selector(confirmEscapeChanged)))
        ])
    }

    private func makePinPage() -> NSView {
        pinMaxStepper = NSStepper()
        pinMaxStepper.minValue = 100
        pinMaxStepper.maxValue = 20000
        pinMaxStepper.increment = 500
        pinMaxStepper.target = self
        pinMaxStepper.action = #selector(pinMaxSizeChanged)
        pinMaxLabel = NSTextField(labelWithString: "")
        pinMaxLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let maxRow = NSStackView(views: [pinMaxStepper, pinMaxLabel])
        maxRow.orientation = .horizontal
        maxRow.spacing = 8

        return page([
            row("最大尺寸", maxRow),
            row("快速缩略图宽 / 高", NSTextField(labelWithString: "75 × 75（可在设置文件调整）")),
            row("滚轮缩放", toggle(#selector(pinWheelZoomChanged))),
            row("平滑缩放", toggle(#selector(pinSmoothScalingChanged))),
            row("新贴图闪烁", toggle(#selector(flashNewPinChanged))),
            row("窗口阴影", toggle(#selector(pinShadowChanged))),
            row("可恢复贴图数", NSTextField(labelWithString: "1（0–20）"))
        ])
    }

    private func makeOutputPage() -> NSView {
        patternField = NSTextField(string: "")
        patternField.target = self
        patternField.action = #selector(patternChanged)
        patternField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        qualitySlider = NSSlider(value: 92, minValue: 30, maxValue: 100,
                                 target: self, action: #selector(qualityChanged))
        qualitySlider.isContinuous = false
        qualitySlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        return page([
            row("自动保存", toggle(#selector(autoSaveChanged))),
            row("文件名模板", patternField),
            row("JPEG 质量", qualitySlider),
            row("快速保存目录", NSButton(title: "选择目录…", target: self, action: #selector(chooseQuickSaveDirectory))),
            row("提示", NSTextField(labelWithString: "模板支持 $yyyy$ $MM$ $dd$ $HH$ $mm$ $ss$"))
        ])
    }

    private func makeControlPage() -> NSView {
        duplicateLabel = NSTextField(labelWithString: "")
        duplicateLabel.textColor = .systemRed
        duplicateLabel.font = .systemFont(ofSize: 11)

        var rows: [NSView] = [
            row("启用全局快捷键", toggle(#selector(hotkeysEnabledChanged)))
        ]
        for key in HotkeyBindingKey.allCases {
            let field = HotkeyField()
            field.onChange = { [weak self] binding in
                self?.hotkeyChanged(key, binding)
            }
            hotkeyFields.append((key, field))
            rows.append(row(key.title, field))
        }
        rows.append(duplicateLabel)
        rows.append(NSTextField(labelWithString: "点击输入框后按下组合键；Delete 清空，Esc 取消。"))
        return page(rows)
    }

    private func makeAboutPage() -> NSView {
        let version = NSTextField(labelWithString: "\(AppInfo.name) \(AppInfo.version)")
        version.font = .systemFont(ofSize: 15, weight: .semibold)
        return page([
            version,
            NSTextField(labelWithString: "macOS 原生版 · 屏幕录制：\(Permissions.screenRecordingGranted ? "已授权" : "未授权")"),
            NSTextField(labelWithString: "辅助功能：\(Permissions.accessibilityGranted ? "已授权" : "未授权")"),
            NSButton(title: "打开日志", target: self, action: #selector(openLog)),
            NSButton(title: "打开配置文件", target: self, action: #selector(openConfig))
        ])
    }

    private func toggle(_ action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = action
        return toggle
    }

    // MARK: - 同步

    private func reload() {
        let settings = SettingsStore.shared.settings
        maskSlider?.doubleValue = Double(settings.maskOpacity)
        zoomStepper?.integerValue = settings.magnifierZoom
        zoomLabel?.stringValue = "\(settings.magnifierZoom)×"
        patternField?.stringValue = settings.fileNamePattern
        qualitySlider?.doubleValue = Double(settings.jpegQuality)
        logPopup?.selectItem(withTitle: settings.logLevel.title)
        if let credentials = MicrosoftCredentials.load() {
            azureKeyField?.stringValue = credentials.key
            azureRegionField?.stringValue = credentials.region
        }
        pinMaxStepper?.integerValue = settings.pinMaxSize
        pinMaxLabel?.stringValue = "\(settings.pinMaxSize) px"

        for (key, field) in hotkeyFields {
            field.binding = binding(for: key, settings: settings)
            field.isInvalid = false
        }
        syncToggles()
    }

    private func binding(for key: HotkeyBindingKey, settings: AppSettings) -> HotkeyBinding {
        switch key {
        case .capture: return settings.captureHotkey
        case .pin: return settings.pinHotkey
        case .ocr: return settings.ocrHotkey
        case .qr: return settings.qrHotkey
        case .translation: return settings.translationHotkey
        }
    }

    private func syncToggles() {
        guard let content = window?.contentView else { return }
        syncToggles(in: content)
    }

    private func syncToggles(in view: NSView) {
        guard let toggle = view as? NSSwitch else {
            for subview in view.subviews { syncToggles(in: subview) }
            return
        }
        let settings = SettingsStore.shared.settings
        let action = toggle.action
        if action == #selector(showCrosshairChanged) { toggle.state = settings.showCrosshair ? .on : .off }
        else if action == #selector(autoMagnifierChanged) { toggle.state = settings.autoMagnifier ? .on : .off }
        else if action == #selector(detectWindowsChanged) { toggle.state = settings.detectWindows ? .on : .off }
        else if action == #selector(captureCursorChanged) { toggle.state = settings.captureCursor ? .on : .off }
        else if action == #selector(confirmEscapeChanged) { toggle.state = settings.confirmEscape ? .on : .off }
        else if action == #selector(autoSaveChanged) { toggle.state = settings.autoSave ? .on : .off }
        else if action == #selector(showToastChanged) { toggle.state = settings.showToast ? .on : .off }
        else if action == #selector(captureAnchorsChanged) { toggle.state = settings.captureAnchors ? .on : .off }
        else if action == #selector(hideOnePixelHintChanged) { toggle.state = settings.hideOnePixelHint ? .on : .off }
        else if action == #selector(startAtLoginChanged) { toggle.state = settings.startAtLogin ? .on : .off }
        else if action == #selector(pinWheelZoomChanged) { toggle.state = settings.pinWheelZoom ? .on : .off }
        else if action == #selector(pinSmoothScalingChanged) { toggle.state = settings.pinSmoothScaling ? .on : .off }
        else if action == #selector(flashNewPinChanged) { toggle.state = settings.flashNewPin ? .on : .off }
        else if action == #selector(pinShadowChanged) { toggle.state = settings.pinShadow ? .on : .off }
        else if action == #selector(hotkeysEnabledChanged) { toggle.state = settings.hotkeysEnabled ? .on : .off }
    }

    // MARK: - 动作

    private func on(_ action: Selector) -> Bool {
        findToggle(action)?.state == .on
    }

    private func findToggle(_ action: Selector) -> NSSwitch? {
        guard let content = window?.contentView else { return nil }
        return findToggle(action, in: content)
    }

    private func findToggle(_ action: Selector, in view: NSView) -> NSSwitch? {
        if let toggle = view as? NSSwitch, toggle.action == action { return toggle }
        for subview in view.subviews {
            if let found = findToggle(action, in: subview) { return found }
        }
        return nil
    }

    @objc private func maskChanged() {
        SettingsStore.shared.update { $0.maskOpacity = Int(self.maskSlider.doubleValue) }
    }

    @objc private func zoomChanged() {
        let value = zoomStepper.integerValue
        zoomLabel.stringValue = "\(value)×"
        SettingsStore.shared.update { $0.magnifierZoom = value }
    }

    @objc private func showCrosshairChanged() {
        SettingsStore.shared.update { $0.showCrosshair = self.on(#selector(self.showCrosshairChanged)) }
    }

    @objc private func autoMagnifierChanged() {
        SettingsStore.shared.update { $0.autoMagnifier = self.on(#selector(self.autoMagnifierChanged)) }
    }

    @objc private func detectWindowsChanged() {
        SettingsStore.shared.update { $0.detectWindows = self.on(#selector(self.detectWindowsChanged)) }
    }

    @objc private func captureCursorChanged() {
        SettingsStore.shared.update { $0.captureCursor = self.on(#selector(self.captureCursorChanged)) }
    }

    @objc private func confirmEscapeChanged() {
        SettingsStore.shared.update { $0.confirmEscape = self.on(#selector(self.confirmEscapeChanged)) }
    }

    @objc private func captureAnchorsChanged() {
        SettingsStore.shared.update { $0.captureAnchors = self.on(#selector(self.captureAnchorsChanged)) }
    }

    @objc private func hideOnePixelHintChanged() {
        SettingsStore.shared.update { $0.hideOnePixelHint = self.on(#selector(self.hideOnePixelHintChanged)) }
    }

    @objc private func showToastChanged() {
        SettingsStore.shared.update { $0.showToast = self.on(#selector(self.showToastChanged)) }
    }

    @objc private func autoSaveChanged() {
        SettingsStore.shared.update { $0.autoSave = self.on(#selector(self.autoSaveChanged)) }
    }

    @objc private func pinWheelZoomChanged() {
        SettingsStore.shared.update { $0.pinWheelZoom = self.on(#selector(self.pinWheelZoomChanged)) }
    }

    @objc private func pinSmoothScalingChanged() {
        SettingsStore.shared.update { $0.pinSmoothScaling = self.on(#selector(self.pinSmoothScalingChanged)) }
    }

    @objc private func flashNewPinChanged() {
        SettingsStore.shared.update { $0.flashNewPin = self.on(#selector(self.flashNewPinChanged)) }
    }

    @objc private func pinShadowChanged() {
        SettingsStore.shared.update { $0.pinShadow = self.on(#selector(self.pinShadowChanged)) }
    }

    @objc private func hotkeysEnabledChanged() {
        SettingsStore.shared.update { $0.hotkeysEnabled = self.on(#selector(self.hotkeysEnabledChanged)) }
    }

    @objc private func logLevelChanged() {
        guard let raw = logPopup.selectedItem?.representedObject as? String,
              let level = LogLevel(rawValue: raw) else { return }
        SettingsStore.shared.update { $0.logLevel = level }
    }

    @objc private func patternChanged() {
        SettingsStore.shared.update { $0.fileNamePattern = self.patternField.stringValue }
    }

    @objc private func qualityChanged() {
        SettingsStore.shared.update { $0.jpegQuality = Int(self.qualitySlider.doubleValue) }
    }

    @objc private func pinMaxSizeChanged() {
        let value = pinMaxStepper.integerValue
        pinMaxLabel.stringValue = "\(value) px"
        SettingsStore.shared.update { $0.pinMaxSize = value }
    }

    @objc private func startAtLoginChanged() {
        let enabled = on(#selector(startAtLoginChanged))
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            SettingsStore.shared.update { $0.startAtLogin = enabled }
        } catch {
            Toast.show("设置开机启动失败：\(error.localizedDescription)")
            syncToggles()
        }
    }

    @objc private func saveAzureKey() {
        MicrosoftCredentials.save(MicrosoftCredentials(key: azureKeyField.stringValue,
                                                       region: azureRegionField.stringValue))
        Toast.show(azureKeyField.stringValue.isEmpty ? "已清除微软翻译密钥" : "已保存微软翻译密钥")
    }

    @objc private func chooseQuickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            SettingsStore.shared.update { $0.quickSaveDirectory = url.path }
        }
    }

    @objc private func openScreenPermission() { Permissions.openScreenRecordingSettings() }
    @objc private func openAccessibilityPermission() { Permissions.openAccessibilitySettings() }
    @objc private func openLog() { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logFile]) }
    @objc private func openConfig() { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.settingsFile]) }

    private func hotkeyChanged(_ key: HotkeyBindingKey, _ binding: HotkeyBinding) {
        let settings = SettingsStore.shared.settings
        var others: [HotkeyBinding] = []
        for other in HotkeyBindingKey.allCases where other != key {
            others.append(self.binding(for: other, settings: settings))
        }
        if binding.isSet, others.contains(binding) {
            duplicateLabel.stringValue = "该组合键与其他功能重复"
            for (fieldKey, field) in hotkeyFields where fieldKey == key {
                field.isInvalid = true
            }
            return
        }
        duplicateLabel.stringValue = ""
        for (fieldKey, field) in hotkeyFields where fieldKey == key {
            field.isInvalid = false
        }
        SettingsStore.shared.update {
            switch key {
            case .capture: $0.captureHotkey = binding
            case .pin: $0.pinHotkey = binding
            case .ocr: $0.ocrHotkey = binding
            case .qr: $0.qrHotkey = binding
            case .translation: $0.translationHotkey = binding
            }
        }
    }
}
