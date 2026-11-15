import Foundation

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case off
    case error
    case normal
    case debug

    public var title: String {
        switch self {
        case .off: return "关闭"
        case .error: return "仅错误"
        case .normal: return "常规"
        case .debug: return "调试"
        }
    }
}

/// 单文件日志，超过 2MB 轮转成 .old。
public final class AppLog {
    public static let shared = AppLog()

    /// 由设置驱动，命令行/启动时设置。
    public var level: LogLevel = .normal

    private let queue = DispatchQueue(label: "com.sniplite.applog")
    private let maxBytes: UInt64 = 2_000_000
    private let formatter: DateFormatter

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    public func write(_ message: String, level messageLevel: LogLevel = .normal, error: Error? = nil) {
        guard shouldWrite(messageLevel) else { return }
        var line = "[\(formatter.string(from: Date()))] \(message)"
        if let error { line += " — \(error.localizedDescription)" }
        line += "\n"

        queue.async {
            if messageLevel == .error, let error {
                NSLog("SnipLite: %@ — %@", message, String(describing: error))
            }
            self.rotateIfNeeded()
            do {
                try self.append(line)
            } catch {
                NSLog("SnipLite: 日志写入失败 \(error)")
            }
        }
    }

    public func writeError(_ message: String, error: Error) {
        write(message, level: .error, error: error)
    }

    private func shouldWrite(_ messageLevel: LogLevel) -> Bool {
        switch level {
        case .off: return false
        case .error: return messageLevel == .error
        case .normal: return messageLevel != .debug
        case .debug: return true
        }
    }

    private func rotateIfNeeded() {
        let manager = FileManager.default
        guard let size = try? manager.attributesOfItem(atPath: AppPaths.logFile.path)[.size] as? UInt64,
              size > maxBytes else { return }
        try? manager.removeItem(at: AppPaths.logRotatedFile)
        try? manager.moveItem(at: AppPaths.logFile, to: AppPaths.logRotatedFile)
    }

    private func append(_ line: String) throws {
        try FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: AppPaths.logFile.path) {
            let handle = try FileHandle(forWritingTo: AppPaths.logFile)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: AppPaths.logFile, options: .atomic)
        }
    }
}
