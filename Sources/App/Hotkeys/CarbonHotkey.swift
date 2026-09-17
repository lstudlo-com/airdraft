import Carbon.HIToolbox
import Foundation
import AirdraftCore
import os

/// Key-combination hotkeys via Carbon `RegisterEventHotKey`. Needs no
/// permission, delivers both press and release, and swallows the combo.
/// Cannot express modifier-only keys or fn; those use the event tap.
final class CarbonHotkey {
    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "hotkey")
    private static var registry: [UInt32: CarbonHotkey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init() {
        id = CarbonHotkey.nextID
        CarbonHotkey.nextID += 1
    }

    deinit { unregister() }

    static func canRegister(_ hotkey: Hotkey) -> Bool {
        !hotkey.isModifierOnly && hotkey.modifiers & Hotkey.maskSecondaryFn == 0
    }

    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        guard CarbonHotkey.canRegister(hotkey) else { return false }
        CarbonHotkey.installHandlerIfNeeded()

        var mods: UInt32 = 0
        if hotkey.modifiers & Hotkey.maskCommand != 0 { mods |= UInt32(cmdKey) }
        if hotkey.modifiers & Hotkey.maskAlternate != 0 { mods |= UInt32(optionKey) }
        if hotkey.modifiers & Hotkey.maskControl != 0 { mods |= UInt32(controlKey) }
        if hotkey.modifiers & Hotkey.maskShift != 0 { mods |= UInt32(shiftKey) }

        let hotKeyID = EventHotKeyID(signature: 0x5452_5342, id: id) // 'TRSB'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(hotkey.keyCode), mods, hotKeyID, GetEventDispatcherTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            CarbonHotkey.log.error("RegisterEventHotKey failed status=\(status) hotkey=\(hotkey.displayString)")
            return false
        }
        ref = newRef
        CarbonHotkey.registry[id] = self
        CarbonHotkey.log.notice("Carbon hotkey registered: \(hotkey.displayString, privacy: .public)")
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        CarbonHotkey.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard let instance = CarbonHotkey.registry[hotKeyID.id] else { return noErr }
            switch GetEventKind(event) {
            case UInt32(kEventHotKeyPressed):
                CarbonHotkey.log.notice("hotkey pressed")
                instance.onPress?()
            case UInt32(kEventHotKeyReleased):
                CarbonHotkey.log.notice("hotkey released")
                instance.onRelease?()
            default: break
            }
            return noErr
        }, types.count, &types, nil, nil)
        handlerInstalled = status == noErr
        if status != noErr { log.error("InstallEventHandler failed status=\(status)") }
    }
}
