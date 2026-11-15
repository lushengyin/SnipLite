import Foundation

public enum AppPaths {
    public static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SnipLite", isDirectory: true)
    }()

    public static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    public static var logFile: URL { supportDirectory.appendingPathComponent("app.log") }
    public static var logRotatedFile: URL { supportDirectory.appendingPathComponent("app.log.old") }

    public static var tempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SnipLite", isDirectory: true)
    }

    public static func ensureDirectories() {
        let manager = FileManager.default
        for directory in [supportDirectory, tempDirectory] {
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                NSLog("SnipLite: 无法创建目录 \(directory.path): \(error)")
            }
        }
    }
}
