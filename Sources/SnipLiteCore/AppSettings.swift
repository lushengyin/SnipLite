import CoreGraphics
import Foundation

// MARK: - 基础值类型

public struct CaptureRegion: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public var isUsable: Bool { width >= 1 && height >= 1 }
}

public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case control, option, shift, command
    }

    public var key: String?
    public var modifiers: [Modifier]

    public init(key: String? = nil, modifiers: [Modifier] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let unset = HotkeyBinding()

    public var isSet: Bool { key?.isEmpty == false }

    /// 按 ⌃⌥⇧⌘ 的顺序输出，与 macOS 惯例一致。
    public var displayText: String {
        guard let key, !key.isEmpty else { return "未设置" }
        let symbols: [Modifier: String] = [.control: "⌃", .option: "⌥", .shift: "⇧", .command: "⌘"]
        let ordered = [Modifier.control, .option, .shift, .command].filter { modifiers.contains($0) }
        return ordered.map { symbols[$0] ?? "" }.joined() + key.uppercased()
    }

    public mutating func normalize() {
        modifiers = [Modifier.control, .option, .shift, .command].filter { modifiers.contains($0) }
        if let key, key.isEmpty { self.key = nil }
    }
}

/// 截图结束动作，对应原版 EnterAction / MiddleClickAction / DoubleClickAction。
public enum CaptureAction: String, Codable, CaseIterable, Sendable {
    case copy
    case pin
    case quickSave
    case none
}

// MARK: - 设置

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = AppSettings.currentSchemaVersion

    // 常规
    public var displayLanguage = "zh-CN"
    public var logLevel: LogLevel = .normal
    public var showToast = true

    // 快捷键（默认按 Mac 习惯）
    public var hotkeysEnabled = true
    public var captureHotkey = HotkeyBinding(key: "A", modifiers: [.control, .option])
    public var pinHotkey = HotkeyBinding(key: "S", modifiers: [.control, .option])
    public var ocrHotkey = HotkeyBinding(key: "O", modifiers: [.control, .option])
    public var qrHotkey = HotkeyBinding(key: "Q", modifiers: [.control, .option])
    public var translationHotkey = HotkeyBinding(key: "T", modifiers: [.control, .option])

    // 截图外观
    public var maskOpacity = 110              // 0...200
    public var magnifierZoom = 6              // 2...16
    public var showCrosshair = true
    public var autoMagnifier = true
    public var captureBorderWidth = 1         // 1...10
    public var captureAnchors = true
    public var hideOnePixelHint = true
    public var captureCursor = false
    public var detectWindows = true
    public var detectElements = true
    public var exitCaptureOnDeactivate = false
    public var disableCaptureWheel = false
    public var confirmEscape = false

    // 动作
    public var copyAfterCapture = true
    public var enterAction: CaptureAction = .copy
    public var enterExit = true
    public var doubleClickAction: CaptureAction = .copy
    public var doubleClickExit = true
    public var middleClickAction: CaptureAction = .pin
    public var middleClickExit = true

    // 识别与翻译
    public var ocrLanguage = "zh-Hans"
    public var translationSourceLanguage = "en"
    public var translationTargetLanguage = "zh-CN"
    public var translationProvider: TranslationProviderKind = .google

    // 贴图
    public var pinMaxSize = 12000
    public var thumbnailWidth = 75
    public var thumbnailHeight = 75
    public var pinWheelZoom = true
    public var pinSmoothScaling = true
    public var flashNewPin = true
    public var recoverablePins = 1
    public var pinShadow = true

    // 启动
    public var startAtLogin = false

    // 历史
    public var historyImageLimit = 20         // 0...100
    public var historyRegionLimit = 8         // 0...100
    public var cycleHistoryRegions = false
    public var recentRegions: [CaptureRegion] = []

    // 输出
    public var saveDirectory = AppSettings.defaultSaveDirectory
    public var quickSaveDirectory = AppSettings.defaultQuickSaveDirectory
    public var autoSave = false
    public var fileNamePattern = "SnipLite_$yyyy-MM-dd_HH-mm-ss$"
    public var jpegQuality = 92               // 30...100

    public init() {}

    public static var defaultSaveDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/SnipLite", isDirectory: true).path
    }

    public static var defaultQuickSaveDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/SnipLite", isDirectory: true).path
    }

    /// 加载后的统一收口：夹取范围、修正枚举、清理最近选区。
    public mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion

        maskOpacity = min(max(maskOpacity, 0), 200)
        magnifierZoom = min(max(magnifierZoom, 2), 16)
        captureBorderWidth = min(max(captureBorderWidth, 1), 10)
        historyImageLimit = min(max(historyImageLimit, 0), 100)
        historyRegionLimit = min(max(historyRegionLimit, 0), 100)
        jpegQuality = min(max(jpegQuality, 30), 100)

        captureHotkey.normalize()
        pinHotkey.normalize()
        ocrHotkey.normalize()
        qrHotkey.normalize()
        translationHotkey.normalize()

        if saveDirectory.isEmpty { saveDirectory = Self.defaultSaveDirectory }
        if quickSaveDirectory.isEmpty { quickSaveDirectory = Self.defaultQuickSaveDirectory }
        if fileNamePattern.isEmpty { fileNamePattern = "SnipLite_$yyyy-MM-dd_HH-mm-ss$" }

        var seen = Set<CaptureRegion>()
        var cleaned: [CaptureRegion] = []
        for region in recentRegions where region.isUsable {
            if seen.insert(region).inserted { cleaned.append(region) }
        }
        let limit = historyRegionLimit
        recentRegions = limit == 0 ? [] : Array(cleaned.prefix(limit))
    }

    public mutating func rememberRegion(_ region: CaptureRegion) {
        guard region.isUsable else { return }
        recentRegions.removeAll { $0 == region }
        recentRegions.insert(region, at: 0)
        let limit = historyRegionLimit
        recentRegions = limit == 0 ? [] : Array(recentRegions.prefix(limit))
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, displayLanguage, logLevel, showToast
        case hotkeysEnabled, captureHotkey, pinHotkey, ocrHotkey, qrHotkey, translationHotkey
        case maskOpacity, magnifierZoom, showCrosshair, autoMagnifier, captureBorderWidth
        case captureAnchors, hideOnePixelHint, captureCursor, detectWindows, detectElements
        case exitCaptureOnDeactivate, disableCaptureWheel, confirmEscape
        case copyAfterCapture, enterAction, enterExit, doubleClickAction, doubleClickExit
        case middleClickAction, middleClickExit
        case historyImageLimit, historyRegionLimit, cycleHistoryRegions, recentRegions
        case ocrLanguage, translationSourceLanguage, translationTargetLanguage, translationProvider
        case pinMaxSize, thumbnailWidth, thumbnailHeight, pinWheelZoom, pinSmoothScaling
        case flashNewPin, recoverablePins, pinShadow, startAtLogin
        case saveDirectory, quickSaveDirectory, autoSave, fileNamePattern, jpegQuality
    }

    /// 缺失字段一律回退默认值——Windows 版也是这样容忍旧配置的。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        displayLanguage = try c.decodeIfPresent(String.self, forKey: .displayLanguage) ?? d.displayLanguage
        logLevel = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? d.logLevel
        showToast = try c.decodeIfPresent(Bool.self, forKey: .showToast) ?? d.showToast
        hotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? d.hotkeysEnabled
        captureHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .captureHotkey) ?? d.captureHotkey
        pinHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .pinHotkey) ?? d.pinHotkey
        ocrHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .ocrHotkey) ?? d.ocrHotkey
        qrHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .qrHotkey) ?? d.qrHotkey
        translationHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .translationHotkey) ?? d.translationHotkey
        maskOpacity = try c.decodeIfPresent(Int.self, forKey: .maskOpacity) ?? d.maskOpacity
        magnifierZoom = try c.decodeIfPresent(Int.self, forKey: .magnifierZoom) ?? d.magnifierZoom
        showCrosshair = try c.decodeIfPresent(Bool.self, forKey: .showCrosshair) ?? d.showCrosshair
        autoMagnifier = try c.decodeIfPresent(Bool.self, forKey: .autoMagnifier) ?? d.autoMagnifier
        captureBorderWidth = try c.decodeIfPresent(Int.self, forKey: .captureBorderWidth) ?? d.captureBorderWidth
        captureAnchors = try c.decodeIfPresent(Bool.self, forKey: .captureAnchors) ?? d.captureAnchors
        hideOnePixelHint = try c.decodeIfPresent(Bool.self, forKey: .hideOnePixelHint) ?? d.hideOnePixelHint
        captureCursor = try c.decodeIfPresent(Bool.self, forKey: .captureCursor) ?? d.captureCursor
        detectWindows = try c.decodeIfPresent(Bool.self, forKey: .detectWindows) ?? d.detectWindows
        detectElements = try c.decodeIfPresent(Bool.self, forKey: .detectElements) ?? d.detectElements
        exitCaptureOnDeactivate = try c.decodeIfPresent(Bool.self, forKey: .exitCaptureOnDeactivate) ?? d.exitCaptureOnDeactivate
        disableCaptureWheel = try c.decodeIfPresent(Bool.self, forKey: .disableCaptureWheel) ?? d.disableCaptureWheel
        confirmEscape = try c.decodeIfPresent(Bool.self, forKey: .confirmEscape) ?? d.confirmEscape
        copyAfterCapture = try c.decodeIfPresent(Bool.self, forKey: .copyAfterCapture) ?? d.copyAfterCapture
        enterAction = try c.decodeIfPresent(CaptureAction.self, forKey: .enterAction) ?? d.enterAction
        enterExit = try c.decodeIfPresent(Bool.self, forKey: .enterExit) ?? d.enterExit
        doubleClickAction = try c.decodeIfPresent(CaptureAction.self, forKey: .doubleClickAction) ?? d.doubleClickAction
        doubleClickExit = try c.decodeIfPresent(Bool.self, forKey: .doubleClickExit) ?? d.doubleClickExit
        middleClickAction = try c.decodeIfPresent(CaptureAction.self, forKey: .middleClickAction) ?? d.middleClickAction
        middleClickExit = try c.decodeIfPresent(Bool.self, forKey: .middleClickExit) ?? d.middleClickExit
        historyImageLimit = try c.decodeIfPresent(Int.self, forKey: .historyImageLimit) ?? d.historyImageLimit
        historyRegionLimit = try c.decodeIfPresent(Int.self, forKey: .historyRegionLimit) ?? d.historyRegionLimit
        cycleHistoryRegions = try c.decodeIfPresent(Bool.self, forKey: .cycleHistoryRegions) ?? d.cycleHistoryRegions
        recentRegions = try c.decodeIfPresent([CaptureRegion].self, forKey: .recentRegions) ?? d.recentRegions
        ocrLanguage = try c.decodeIfPresent(String.self, forKey: .ocrLanguage) ?? d.ocrLanguage
        translationSourceLanguage = try c.decodeIfPresent(String.self, forKey: .translationSourceLanguage) ?? d.translationSourceLanguage
        translationTargetLanguage = try c.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? d.translationTargetLanguage
        translationProvider = try c.decodeIfPresent(TranslationProviderKind.self, forKey: .translationProvider) ?? d.translationProvider
        pinMaxSize = try c.decodeIfPresent(Int.self, forKey: .pinMaxSize) ?? d.pinMaxSize
        thumbnailWidth = try c.decodeIfPresent(Int.self, forKey: .thumbnailWidth) ?? d.thumbnailWidth
        thumbnailHeight = try c.decodeIfPresent(Int.self, forKey: .thumbnailHeight) ?? d.thumbnailHeight
        pinWheelZoom = try c.decodeIfPresent(Bool.self, forKey: .pinWheelZoom) ?? d.pinWheelZoom
        pinSmoothScaling = try c.decodeIfPresent(Bool.self, forKey: .pinSmoothScaling) ?? d.pinSmoothScaling
        flashNewPin = try c.decodeIfPresent(Bool.self, forKey: .flashNewPin) ?? d.flashNewPin
        recoverablePins = try c.decodeIfPresent(Int.self, forKey: .recoverablePins) ?? d.recoverablePins
        pinShadow = try c.decodeIfPresent(Bool.self, forKey: .pinShadow) ?? d.pinShadow
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? d.startAtLogin
        saveDirectory = try c.decodeIfPresent(String.self, forKey: .saveDirectory) ?? d.saveDirectory
        quickSaveDirectory = try c.decodeIfPresent(String.self, forKey: .quickSaveDirectory) ?? d.quickSaveDirectory
        autoSave = try c.decodeIfPresent(Bool.self, forKey: .autoSave) ?? d.autoSave
        fileNamePattern = try c.decodeIfPresent(String.self, forKey: .fileNamePattern) ?? d.fileNamePattern
        jpegQuality = try c.decodeIfPresent(Int.self, forKey: .jpegQuality) ?? d.jpegQuality
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(displayLanguage, forKey: .displayLanguage)
        try c.encode(logLevel, forKey: .logLevel)
        try c.encode(showToast, forKey: .showToast)
        try c.encode(hotkeysEnabled, forKey: .hotkeysEnabled)
        try c.encode(captureHotkey, forKey: .captureHotkey)
        try c.encode(pinHotkey, forKey: .pinHotkey)
        try c.encode(ocrHotkey, forKey: .ocrHotkey)
        try c.encode(qrHotkey, forKey: .qrHotkey)
        try c.encode(translationHotkey, forKey: .translationHotkey)
        try c.encode(maskOpacity, forKey: .maskOpacity)
        try c.encode(magnifierZoom, forKey: .magnifierZoom)
        try c.encode(showCrosshair, forKey: .showCrosshair)
        try c.encode(autoMagnifier, forKey: .autoMagnifier)
        try c.encode(captureBorderWidth, forKey: .captureBorderWidth)
        try c.encode(captureAnchors, forKey: .captureAnchors)
        try c.encode(hideOnePixelHint, forKey: .hideOnePixelHint)
        try c.encode(captureCursor, forKey: .captureCursor)
        try c.encode(detectWindows, forKey: .detectWindows)
        try c.encode(detectElements, forKey: .detectElements)
        try c.encode(exitCaptureOnDeactivate, forKey: .exitCaptureOnDeactivate)
        try c.encode(disableCaptureWheel, forKey: .disableCaptureWheel)
        try c.encode(confirmEscape, forKey: .confirmEscape)
        try c.encode(copyAfterCapture, forKey: .copyAfterCapture)
        try c.encode(enterAction, forKey: .enterAction)
        try c.encode(enterExit, forKey: .enterExit)
        try c.encode(doubleClickAction, forKey: .doubleClickAction)
        try c.encode(doubleClickExit, forKey: .doubleClickExit)
        try c.encode(middleClickAction, forKey: .middleClickAction)
        try c.encode(middleClickExit, forKey: .middleClickExit)
        try c.encode(historyImageLimit, forKey: .historyImageLimit)
        try c.encode(historyRegionLimit, forKey: .historyRegionLimit)
        try c.encode(cycleHistoryRegions, forKey: .cycleHistoryRegions)
        try c.encode(recentRegions, forKey: .recentRegions)
        try c.encode(ocrLanguage, forKey: .ocrLanguage)
        try c.encode(translationSourceLanguage, forKey: .translationSourceLanguage)
        try c.encode(translationTargetLanguage, forKey: .translationTargetLanguage)
        try c.encode(translationProvider, forKey: .translationProvider)
        try c.encode(pinMaxSize, forKey: .pinMaxSize)
        try c.encode(thumbnailWidth, forKey: .thumbnailWidth)
        try c.encode(thumbnailHeight, forKey: .thumbnailHeight)
        try c.encode(pinWheelZoom, forKey: .pinWheelZoom)
        try c.encode(pinSmoothScaling, forKey: .pinSmoothScaling)
        try c.encode(flashNewPin, forKey: .flashNewPin)
        try c.encode(recoverablePins, forKey: .recoverablePins)
        try c.encode(pinShadow, forKey: .pinShadow)
        try c.encode(startAtLogin, forKey: .startAtLogin)
        try c.encode(saveDirectory, forKey: .saveDirectory)
        try c.encode(quickSaveDirectory, forKey: .quickSaveDirectory)
        try c.encode(autoSave, forKey: .autoSave)
        try c.encode(fileNamePattern, forKey: .fileNamePattern)
        try c.encode(jpegQuality, forKey: .jpegQuality)
    }
}
