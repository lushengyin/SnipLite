import AppKit
import Carbon.HIToolbox
import SnipLiteCore

/// 全局热键：Carbon RegisterEventHotKey，不需要辅助功能权限。
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var registrations: [(ref: EventHotKeyRef, id: UInt32)] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private(set) var failures: [String: String] = [:]

    private let signature: OSType = 0x534E4950 // "SNIP"

    func apply(_ settings: AppSettings) {
        unregisterAll()
        failures.removeAll()
        installHandlerIfNeeded()
        guard settings.hotkeysEnabled else { return }

        register("截图", settings.captureHotkey) {
            CaptureSession.start(mode: .capture)
        }
        register("贴图", settings.pinHotkey) {
            Task { @MainActor in PinController.shared.pasteFromClipboard() }
        }
        register("文字识别", settings.ocrHotkey) {
            CaptureSession.start(mode: .ocr)
        }
        register("二维码识别", settings.qrHotkey) {
            CaptureSession.start(mode: .qr)
        }
        register("截图翻译", settings.translationHotkey) {
            CaptureSession.start(mode: .translation)
        }
    }

    private func register(_ name: String, _ binding: HotkeyBinding, action: @escaping () -> Void) {
        guard let key = binding.key, !key.isEmpty else { return }
        guard let code = Self.keyCode(for: key) else {
            failures[name] = "不支持的按键：\(key)"
            return
        }

        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(code,
                                         Self.carbonModifiers(binding.modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            failures[name] = "已被其他程序占用"
            return
        }
        registrations.append((ref, id))
        actions[id] = action
    }

    private func unregisterAll() {
        for registration in registrations {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let action = center.actions[hotKeyID.id]
            DispatchQueue.main.async { action?() }
            return noErr
        }, 1, &eventType, userData, &eventHandler)
    }

    // MARK: - 键位映射

    private static func carbonModifiers(_ modifiers: [HotkeyBinding.Modifier]) -> UInt32 {
        var result: UInt32 = 0
        for modifier in modifiers {
            switch modifier {
            case .control: result |= UInt32(controlKey)
            case .option: result |= UInt32(optionKey)
            case .shift: result |= UInt32(shiftKey)
            case .command: result |= UInt32(cmdKey)
            }
        }
        return result
    }

    private static func keyCode(for key: String) -> UInt32? {
        let table: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
            "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
            "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
            "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
            "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5,
            "F6": kVK_F6, "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10,
            "F11": kVK_F11, "F12": kVK_F12, "F13": kVK_F13, "F14": kVK_F14,
            "F15": kVK_F15, "F16": kVK_F16, "F17": kVK_F17, "F18": kVK_F18,
            "F19": kVK_F19, "F20": kVK_F20,
            "SPACE": kVK_Space, "TAB": kVK_Tab, "RETURN": kVK_Return,
            "ESC": kVK_Escape, "DELETE": kVK_Delete,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, ",": kVK_ANSI_Comma,
            ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon,
            "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave
        ]
        return table[key.uppercased()].map(UInt32.init)
    }
}
