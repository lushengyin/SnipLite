import Foundation

/// 加载/保存设置：
/// - 文件损坏静默回退默认值
/// - AutoBackup 时先复制 .bak
/// - 先写 .tmp 再原子替换
public final class SettingsStore {
    public static let shared = SettingsStore()

    public private(set) var settings: AppSettings
    public var onChange: ((AppSettings) -> Void)?

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init(fileURL: URL = AppPaths.settingsFile) {
        self.fileURL = fileURL
        self.settings = AppSettings()
        self.settings = load()
    }

    private let fileURL: URL

    public func reload() {
        settings = load()
    }

    /// 改完即存盘并广播（即时保存，没有确定/取消）。
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        copy.normalize()
        settings = copy
        save()
        onChange?(settings)
    }

    public func save() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: fileURL.path) {
                let backup = fileURL.appendingPathExtension("bak")
                try? fileManager.removeItem(at: backup)
                try? fileManager.copyItem(at: fileURL, to: backup)
            }
            let data = try encoder.encode(settings)
            let temp = fileURL.appendingPathExtension("tmp")
            try data.write(to: temp, options: .atomic)
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
        } catch {
            AppLog.shared.writeError("保存设置失败", error: error)
        }
    }

    /// 外部显式写盘（测试/迁移用），不做备份。
    public func write(_ settings: AppSettings, to url: URL) throws {
        var normalized = settings
        normalized.normalize()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let data = try encoder.encode(normalized)
        try data.write(to: url, options: .atomic)
    }

    private func load() -> AppSettings {
        guard fileManager.fileExists(atPath: fileURL.path) else { return AppSettings() }
        do {
            let data = try Data(contentsOf: fileURL)
            var loaded = try JSONDecoder().decode(AppSettings.self, from: data)
            loaded.normalize()
            return loaded
        } catch {
            AppLog.shared.writeError("读取设置失败，已回退默认值", error: error)
            return AppSettings()
        }
    }
}
