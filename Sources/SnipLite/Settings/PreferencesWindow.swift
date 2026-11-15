import AppKit
import QuartzCore
import ServiceManagement
import SnipLiteCore

private enum SettingsPage: Int, CaseIterable {
    case general, capture, pin, output, control, about

    var title: String {
        switch self {
        case .general: return "通用"
        case .capture: return "截屏"
        case .pin: return "贴图"
        case .output: return "输出"
        case .control: return "快捷键"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "viewfinder"
        case .pin: return "pin"
        case .output: return "square.and.arrow.up"
        case .control: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

/// 设置窗口：顶部图标导航轨 + 下方分组卡片。
@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

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

    // MARK: - 控件

    private var maskSlider: NSSlider!
    private var maskValue: NSTextField!
    private var zoomStepper: NSStepper!
    private var zoomLabel: NSTextField!
    private var patternField: NSTextField!
    private var qualitySlider: NSSlider!
    private var qualityValue: NSTextField!
    private var logPopup: NSPopUpButton!
    private var pinMaxStepper: NSStepper!
    private var pinMaxLabel: NSTextField!
    private var azureKeyField: NSSecureTextField!
    private var azureRegionField: NSTextField!
    private var hotkeyFields: [(HotkeyBindingKey, HotkeyField)] = []
    private var duplicateLabel: NSTextField!
    private var fieldBoxes: [ObjectIdentifier: FieldBox] = [:]

    // 布局
    private var navItems: [SettingsPage: NavItemView] = [:]
    private var indicator: NSView!
    private var pageViews: [SettingsPage: NSView] = [:]
    private var currentPage: SettingsPage = .general

    // 尺寸
    private let windowSize = NSSize(width: 740, height: 620)
    private let railHeight: CGFloat = 44
    private let navItemSize = NSSize(width: 92, height: 32)
    private let contentInset: CGFloat = 28
    private let headerHeight: CGFloat = 100
    private var pageHeights: [SettingsPage: CGFloat] = [:]

    private init() {
        let window = SettingsWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                                    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                    backing: .buffered,
                                    defer: false)
        window.title = "SnipLite 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.onSelectPage = { [weak self] index in
            guard let page = SettingsPage(rawValue: index) else { return }
            self?.select(page)
        }
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 骨架

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let railWidth = CGFloat(SettingsPage.allCases.count) * navItemSize.width + 12
        let rail = RailBackgroundView(frame: NSRect(
            x: (windowSize.width - railWidth) / 2,
            y: windowSize.height - 26 - railHeight,
            width: railWidth,
            height: railHeight
        ))
        rail.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        indicator = NavIndicatorView(frame: NSRect(x: 6, y: 6,
                                                   width: navItemSize.width, height: navItemSize.height))
        rail.addSubview(indicator)

        for page in SettingsPage.allCases {
            let item = NavItemView(page: page, size: navItemSize)
            item.frame.origin = NSPoint(x: 6 + CGFloat(page.rawValue) * navItemSize.width, y: 6)
            item.onSelect = { [weak self] page in self?.select(page) }
            rail.addSubview(item)
            navItems[page] = item
        }
        content.addSubview(rail)

        let pageArea = NSView(frame: NSRect(x: 0, y: 0,
                                           width: windowSize.width,
                                           height: windowSize.height - headerHeight))
        pageArea.autoresizingMask = [.width, .height]
        content.addSubview(pageArea)

        let builders: [SettingsPage: () -> NSView] = [
            .general: makeGeneralPage,
            .capture: makeCapturePage,
            .pin: makePinPage,
            .output: makeOutputPage,
            .control: makeControlPage,
            .about: makeAboutPage
        ]
        for (page, build) in builders {
            let scroll = makeScrollPage(build())
            scroll.frame = pageArea.bounds
            scroll.autoresizingMask = [.width, .height]
            scroll.isHidden = page != currentPage
            pageArea.addSubview(scroll)
            pageViews[page] = scroll
        }
        pageArea.addSubview(pageViews[.general]!)
        navItems[currentPage]?.isSelected = true

        // 窗口高度跟随页面内容，避免短页面下方留一大片空白。
        layoutPageHeights()
        resizeWindow(to: currentPage, animated: false)
        window?.center()
    }

    private func layoutPageHeights() {
        for (page, view) in pageViews {
            view.layoutSubtreeIfNeeded()
            guard let scroll = view as? NSScrollView, let document = scroll.documentView else { continue }
            document.layoutSubtreeIfNeeded()
            let height = document.fittingSize.height
            pageHeights[page] = min(max(height + headerHeight, 420), 760)
        }
    }

    private func pageHeight(for page: SettingsPage) -> CGFloat {
        pageHeights[page] ?? windowSize.height
    }

    private func resizeWindow(to page: SettingsPage, animated: Bool) {
        guard let window else { return }
        if pageHeights[page] == nil { layoutPageHeights() }
        let target = pageHeight(for: page)
        var frame = window.frame
        guard abs(frame.height - target) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height = target
        frame.origin.y = top - target
        window.setFrame(frame, display: true, animate: animated)
    }

    private func select(_ page: SettingsPage) {
        guard page != currentPage else { return }
        currentPage = page

        for (key, item) in navItems {
            item.isSelected = (key == page)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            indicator.animator().setFrameOrigin(
                NSPoint(x: 6 + CGFloat(page.rawValue) * navItemSize.width, y: 6)
            )
        }

        for (key, view) in pageViews where key != page {
            view.isHidden = true
        }
        guard let incoming = pageViews[page] else { return }
        incoming.isHidden = false
        incoming.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            incoming.animator().alphaValue = 1
        }
        resizeWindow(to: page, animated: true)
    }

    // MARK: - 页面骨架

    private func makeScrollPage(_ content: NSView) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0,
                                                width: windowSize.width,
                                                height: windowSize.height - headerHeight))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(outer)

        content.translatesAutoresizingMaskIntoConstraints = false
        outer.addArrangedSubview(content)

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            outer.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: contentInset),
            outer.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -contentInset),
            outer.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            outer.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: outer.widthAnchor)
        ])
        return scroll
    }

    /// 一页 = 若干「标题 + 卡片 + 说明」分组。
    private func page(_ sections: [PageSection]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        for (index, section) in sections.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(spacer(20))
            }
            if let title = section.title {
                let header = NSTextField(labelWithString: title)
                header.font = .systemFont(ofSize: 12, weight: .semibold)
                header.textColor = .secondaryLabelColor
                let wrapper = wrapVertical(header, top: 0, bottom: -6, leading: 4)
                stack.addArrangedSubview(wrapper)
                wrapper.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }

            let card = cardView(rows: section.rows)
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            if let hint = section.hint {
                let label = NSTextField(wrappingLabelWithString: hint)
                label.font = .systemFont(ofSize: 11)
                label.textColor = .tertiaryLabelColor
                label.preferredMaxLayoutWidth = windowSize.width - contentInset * 2 - 8
                let wrapper = wrapVertical(label, top: 7, bottom: 0, leading: 4, trailing: -4)
                stack.addArrangedSubview(wrapper)
                wrapper.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        return stack
    }

    private func wrapVertical(_ view: NSView, top: CGFloat, bottom: CGFloat,
                              leading: CGFloat, trailing: CGFloat = 0) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        var constraints = [
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: leading),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: top),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: bottom)
        ]
        constraints.append(trailing == 0
            ? view.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor)
            : view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: trailing))
        NSLayoutConstraint.activate(constraints)
        return wrapper
    }

    private func cardView(rows: [NSView]) -> NSView {
        let card = CardBackgroundView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4)
        ])

        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return card
    }

    private func row(_ title: String, _ control: NSView, controlWidth: CGFloat? = nil) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let container = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12)
        ])
        if let controlWidth {
            control.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        }
        return container
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func toggle(_ action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = action
        return toggle
    }

    private func valueLabel(_ text: String = "", width: CGFloat = 38) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    /// 圆角内嵌输入框，外观与卡片保持一致。
    private func fieldBox(_ field: NSTextField, width: CGFloat) -> NSView {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.delegate = self
        let box = FieldBox(field: field, width: width)
        fieldBoxes[ObjectIdentifier(field)] = box
        return box
    }

    // MARK: - 通用

    private func makeGeneralPage() -> NSView {
        logPopup = NSPopUpButton()
        for level in LogLevel.allCases {
            logPopup.addItem(withTitle: level.title)
            logPopup.lastItem?.representedObject = level.rawValue
        }
        logPopup.target = self
        logPopup.action = #selector(logLevelChanged)

        let permissionButtons = NSStackView(views: [
            button("屏幕录制…", #selector(openScreenPermission)),
            button("辅助功能…", #selector(openAccessibilityPermission))
        ])
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 8

        azureKeyField = NSSecureTextField(string: "")
        azureKeyField.placeholderString = "密钥"
        azureRegionField = NSTextField(string: "")
        azureRegionField.placeholderString = "区域"
        let keyBox = fieldBox(azureKeyField, width: 220)
        let regionBox = fieldBox(azureRegionField, width: 130)
        let keyRow = NSStackView(views: [keyBox, regionBox,
                                         button("保存", #selector(saveAzureKey))])
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 8

        return page([
            PageSection(title: "启动与提示", rows: [
                row("开机启动", toggle(#selector(startAtLoginChanged))),
                row("显示操作提示", toggle(#selector(showToastChanged))),
                row("日志级别", logPopup, controlWidth: 150)
            ], hint: "开机启动使用系统登录项；日志写入应用支持目录。"),
            PageSection(title: "系统权限", rows: [
                row("屏幕录制 / 辅助功能", permissionButtons)
            ], hint: "截图需要屏幕录制权限；窗口检测与全局快捷键需要辅助功能权限。"),
            PageSection(title: "微软翻译", rows: [
                row("密钥与区域", keyRow)
            ], hint: "密钥保存在系统钥匙串，仅在调用微软翻译接口时使用。")
        ])
    }

    // MARK: - 截屏

    private func makeCapturePage() -> NSView {
        maskSlider = NSSlider(value: 110, minValue: 0, maxValue: 200,
                              target: self, action: #selector(maskChanged))
        maskSlider.isContinuous = false
        maskSlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        maskValue = valueLabel("110")
        let maskRow = NSStackView(views: [maskSlider, maskValue])
        maskRow.orientation = .horizontal
        maskRow.spacing = 10

        zoomStepper = NSStepper()
        zoomStepper.minValue = 2
        zoomStepper.maxValue = 16
        zoomStepper.target = self
        zoomStepper.action = #selector(zoomChanged)
        zoomLabel = valueLabel("6×")
        let zoomRow = NSStackView(views: [zoomLabel, zoomStepper])
        zoomRow.orientation = .horizontal
        zoomRow.spacing = 8

        return page([
            PageSection(title: "选区", rows: [
                row("遮罩不透明度", maskRow),
                row("放大镜倍数", zoomRow),
                row("全屏十字线", toggle(#selector(showCrosshairChanged))),
                row("选区前自动放大镜", toggle(#selector(autoMagnifierChanged))),
                row("显示选区锚点", toggle(#selector(captureAnchorsChanged)))
            ], hint: "遮罩越不透明，选区对比越强；放大镜用于精确定位边缘。"),
            PageSection(title: "行为", rows: [
                row("隐藏 1×1 提示", toggle(#selector(hideOnePixelHintChanged))),
                row("截图包含光标", toggle(#selector(captureCursorChanged))),
                row("自动检测窗口", toggle(#selector(detectWindowsChanged))),
                row("Esc 时确认退出", toggle(#selector(confirmEscapeChanged)))
            ], hint: "自动检测窗口会在悬停时吸附到窗口边缘。")
        ])
    }

    // MARK: - 贴图

    private func makePinPage() -> NSView {
        pinMaxStepper = NSStepper()
        pinMaxStepper.minValue = 100
        pinMaxStepper.maxValue = 20000
        pinMaxStepper.increment = 500
        pinMaxStepper.target = self
        pinMaxStepper.action = #selector(pinMaxSizeChanged)
        pinMaxLabel = valueLabel("", width: 76)
        let maxRow = NSStackView(views: [pinMaxLabel, pinMaxStepper])
        maxRow.orientation = .horizontal
        maxRow.spacing = 8

        let staticLabel = NSTextField(labelWithString: "75 × 75")
        staticLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        staticLabel.textColor = .secondaryLabelColor

        return page([
            PageSection(title: "尺寸", rows: [
                row("最大尺寸", maxRow),
                row("快速缩略图", staticLabel)
            ], hint: "快速缩略图尺寸可在设置文件中调整。"),
            PageSection(title: "交互", rows: [
                row("滚轮缩放", toggle(#selector(pinWheelZoomChanged))),
                row("平滑缩放", toggle(#selector(pinSmoothScalingChanged))),
                row("新贴图闪烁", toggle(#selector(flashNewPinChanged))),
                row("窗口阴影", toggle(#selector(pinShadowChanged)))
            ], hint: "可恢复贴图数：1（0–20），在设置文件中调整。")
        ])
    }

    // MARK: - 输出

    private func makeOutputPage() -> NSView {
        patternField = NSTextField(string: "")
        patternField.placeholderString = "截图-$yyyy$$MM$$dd$-$HH$$mm$$ss$"
        patternField.target = self
        patternField.action = #selector(patternChanged)
        let patternBox = fieldBox(patternField, width: 300)

        qualitySlider = NSSlider(value: 92, minValue: 30, maxValue: 100,
                                 target: self, action: #selector(qualityChanged))
        qualitySlider.isContinuous = false
        qualitySlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        qualityValue = valueLabel("92")
        let qualityRow = NSStackView(views: [qualitySlider, qualityValue])
        qualityRow.orientation = .horizontal
        qualityRow.spacing = 10

        return page([
            PageSection(title: "保存", rows: [
                row("自动保存", toggle(#selector(autoSaveChanged))),
                row("文件名模板", patternBox),
                row("JPEG 质量", qualityRow),
                row("快速保存目录", button("选择目录…", #selector(chooseQuickSaveDirectory)))
            ], hint: "模板支持 $yyyy$ $MM$ $dd$ $HH$ $mm$ $ss$；PNG 无损，JPEG 按质量压缩。")
        ])
    }

    // MARK: - 快捷键

    private func makeControlPage() -> NSView {
        duplicateLabel = NSTextField(labelWithString: "")
        duplicateLabel.textColor = .systemRed
        duplicateLabel.font = .systemFont(ofSize: 11)

        hotkeyFields.removeAll()
        var rows: [NSView] = [row("启用全局快捷键", toggle(#selector(hotkeysEnabledChanged)))]
        for key in HotkeyBindingKey.allCases {
            let field = HotkeyField()
            field.onChange = { [weak self] binding in
                self?.hotkeyChanged(key, binding)
            }
            hotkeyFields.append((key, field))
            rows.append(row(key.title, field))
        }
        let duplicateWrapper = wrapVertical(duplicateLabel, top: 0, bottom: -8, leading: 14)
        rows.append(duplicateWrapper)

        return page([
            PageSection(title: "全局快捷键", rows: rows,
                        hint: "点击输入框后按下组合键；Delete 清空，Esc 取消。任一组合键不能与其它功能重复。")
        ])
    }

    // MARK: - 关于

    private func makeAboutPage() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let name = NSTextField(labelWithString: AppInfo.name)
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        let version = NSTextField(labelWithString: "版本 \(AppInfo.version)")
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        let tagline = NSTextField(labelWithString: "轻量、原生的 macOS 截图与贴图工具")
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .tertiaryLabelColor
        let titles = NSStackView(views: [name, version, tagline])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 3

        let identity = NSStackView(views: [icon, titles])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 16
        let identityWrapper = wrapVertical(identity, top: 18, bottom: -18, leading: 16)

        let recording = NSTextField(labelWithString: "屏幕录制：\(Permissions.screenRecordingGranted ? "已授权" : "未授权")")
        let accessibility = NSTextField(labelWithString: "辅助功能：\(Permissions.accessibilityGranted ? "已授权" : "未授权")")
        for label in [recording, accessibility] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }
        let status = NSStackView(views: [recording, accessibility])
        status.orientation = .vertical
        status.alignment = .trailing
        status.spacing = 2

        let buttons = NSStackView(views: [
            button("打开日志", #selector(openLog)),
            button("打开配置文件", #selector(openConfig))
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        return page([
            PageSection(title: nil, rows: [identityWrapper], hint: nil),
            PageSection(title: "状态", rows: [
                row("权限", status)
            ], hint: nil),
            PageSection(title: "诊断", rows: [
                row("日志与配置", buttons)
            ], hint: "日志和配置文件都位于 ~/Library/Application Support/SnipLite。")
        ])
    }

    // MARK: - 同步

    private func reload() {
        let settings = SettingsStore.shared.settings
        maskSlider?.doubleValue = Double(settings.maskOpacity)
        maskValue?.stringValue = "\(settings.maskOpacity)"
        zoomStepper?.integerValue = settings.magnifierZoom
        zoomLabel?.stringValue = "\(settings.magnifierZoom)×"
        patternField?.stringValue = settings.fileNamePattern
        qualitySlider?.doubleValue = Double(settings.jpegQuality)
        qualityValue?.stringValue = "\(settings.jpegQuality)"
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
        let value = Int(maskSlider.doubleValue)
        maskValue.stringValue = "\(value)"
        SettingsStore.shared.update { $0.maskOpacity = value }
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
        SettingsStore.shared.update { $0.fileNamePattern = patternField.stringValue }
    }

    @objc private func qualityChanged() {
        let value = Int(qualitySlider.doubleValue)
        qualityValue.stringValue = "\(value)"
        SettingsStore.shared.update { $0.jpegQuality = value }
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

// MARK: - 辅助视图

extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        fieldBoxes[ObjectIdentifier(field)]?.isEditing = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        fieldBoxes[ObjectIdentifier(field)]?.isEditing = false
    }
}

private struct PageSection {
    let title: String?
    let rows: [NSView]
    let hint: String?
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private enum AppearanceKit {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// 卡片背景：绘制时按当前外观取色，浅色白卡、深色微亮面板，避免硬线条。
private final class CardBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = AppearanceKit.isDark(effectiveAppearance)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.08)
        shadow.shadowBlurRadius = dark ? 12 : 9
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        (dark ? NSColor.white.withAlphaComponent(0.075) : NSColor.white).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        (dark ? NSColor.white.withAlphaComponent(0.09)
              : NSColor.separatorColor.withAlphaComponent(0.22)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// 圆角输入框容器：填充色、描边、聚焦状态都按当前外观绘制。
private final class FieldBox: NSView {
    private let field: NSTextField
    var isEditing = false {
        didSet { needsDisplay = true }
    }

    init(field: NSTextField, width: CGFloat) {
        self.field = field
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 28),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let dark = AppearanceKit.isDark(effectiveAppearance)
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (dark ? NSColor.white.withAlphaComponent(0.06)
              : NSColor.labelColor.withAlphaComponent(0.045)).setFill()
        path.fill()

        if isEditing {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.6
        } else {
            (dark ? NSColor.white.withAlphaComponent(0.09)
                  : NSColor.separatorColor.withAlphaComponent(0.22)).setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// 导航轨底：比窗口背景略深/略亮一档的胶囊。
private final class RailBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = AppearanceKit.isDark(effectiveAppearance)
        (dark ? NSColor.white.withAlphaComponent(0.05)
              : NSColor.labelColor.withAlphaComponent(0.045)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// 选中项：浮起的胶囊。
private final class NavIndicatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = AppearanceKit.isDark(effectiveAppearance)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.40 : 0.12)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        (dark ? NSColor.white.withAlphaComponent(0.15) : NSColor.white).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        (dark ? NSColor.white.withAlphaComponent(0.11)
              : NSColor.separatorColor.withAlphaComponent(0.30)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// ⌘1–⌘6 切换页面。
private final class SettingsWindow: NSWindow {
    var onSelectPage: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command,
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters), (1...6).contains(number) {
            onSelectPage?(number - 1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// 顶部导航项：图标 + 文字，悬停与选中态自绘。
private final class NavItemView: NSView {
    let page: SettingsPage
    var onSelect: ((SettingsPage) -> Void)?

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    private var hovering = false {
        didSet { needsDisplay = true }
    }
    private var tracking: NSTrackingArea?

    init(page: SettingsPage, size: NSSize) {
        self.page = page
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onSelect?(page) }

    // MARK: - 辅助功能

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { page.title }
    override func accessibilityPerformPress() -> Bool {
        onSelect?(page)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering && !isSelected {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9).fill()
        }
        let color: NSColor = isSelected ? .labelColor
            : (hovering ? .labelColor : .secondaryLabelColor)

        let palette = NSImage.SymbolConfiguration(paletteColors: [color])
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium).applying(palette)
        let image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let iconRect = NSRect(x: 12, y: (bounds.height - 15) / 2, width: 15, height: 15)
        image?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

        let title = page.title as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: iconRect.maxX + 6, y: (bounds.height - size.height) / 2),
                   withAttributes: attributes)
    }
}
