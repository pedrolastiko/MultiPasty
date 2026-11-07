import AppKit
import Carbon.HIToolbox

/// Global shortcut registered through Carbon: works in every app and needs no
/// Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Shortcut: Equatable {
        var keyCode: UInt32
        /// Carbon modifier mask: cmdKey, shiftKey, optionKey, controlKey
        var modifiers: UInt32
        var label: String
    }

    static let presets: [Shortcut] = [
        Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧V"),
        Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey), label: "⌥V"),
        Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥V"),
        Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey), label: "⌘⌥V")
    ]

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onTrigger: (() -> Void)?

    private(set) var current: Shortcut = HotKeyCenter.presets[0]

    private init() {}

    func start() {
        installHandler()
        let idx = UserDefaults.standard.integer(forKey: "shortcutPreset")
        let preset = HotKeyCenter.presets.indices.contains(idx) ? HotKeyCenter.presets[idx] : HotKeyCenter.presets[0]
        register(preset)
    }

    func selectPreset(_ index: Int) {
        guard HotKeyCenter.presets.indices.contains(index) else { return }
        UserDefaults.standard.set(index, forKey: "shortcutPreset")
        register(HotKeyCenter.presets[index])
    }

    var currentPresetIndex: Int {
        HotKeyCenter.presets.firstIndex(of: current) ?? 0
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), multiPastyHotKeyHandler, 1, &eventType, nil, &handlerRef)
    }

    private func register(_ shortcut: Shortcut) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D505459), id: 1) // 'MPTY'
        let status = RegisterEventHotKey(shortcut.keyCode,
                                         shortcut.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRef = ref
            current = shortcut
        } else {
            NSLog("MultiPasty: impossible d'enregistrer le raccourci \(shortcut.label) (code \(status))")
        }
    }

    fileprivate func fire() {
        onTrigger?()
    }
}

private func multiPastyHotKeyHandler(nextHandler: EventHandlerCallRef?,
                                     event: EventRef?,
                                     userData: UnsafeMutableRawPointer?) -> OSStatus {
    HotKeyCenter.shared.fire()
    return noErr
}
