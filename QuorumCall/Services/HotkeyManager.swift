import Carbon
import AppKit

// Free C function required by Carbon's InstallEventHandler API
private func carbonHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

    var hotkeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )

    let capturedID = hotkeyID.id
    // Carbon events fire on the main run loop thread — use assumeIsolated to satisfy Swift concurrency
    MainActor.assumeIsolated {
        manager.handleFired(id: capturedID)
    }
    return noErr
}

@Observable
final class HotkeyManager {
    var onActivate: ((UUID) -> Void)?

    private var registeredRefs: [UInt32: EventHotKeyRef] = [:]
    private var idToQuorumID: [UInt32: UUID] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }

    deinit {
        unregisterAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }

    func register(quorum: Quorum) {
        guard let keyCode = quorum.shortcutKeyCode,
              let modifiers = quorum.shortcutModifiers else { return }

        unregister(quorumID: quorum.id)

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: fourCharCode("QCAL"), id: id)
        RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &ref
        )

        if let ref {
            registeredRefs[id] = ref
            idToQuorumID[id] = quorum.id
        }
    }

    func unregister(quorumID: UUID) {
        guard let entry = idToQuorumID.first(where: { $0.value == quorumID }) else { return }
        if let ref = registeredRefs[entry.key] { UnregisterEventHotKey(ref) }
        registeredRefs.removeValue(forKey: entry.key)
        idToQuorumID.removeValue(forKey: entry.key)
    }

    func unregisterAll() {
        registeredRefs.values.forEach { UnregisterEventHotKey($0) }
        registeredRefs.removeAll()
        idToQuorumID.removeAll()
    }

    func handleFired(id: UInt32) {
        guard let quorumID = idToQuorumID[id] else { return }
        onActivate?(quorumID)
    }

    // MARK: - Shortcut Helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func displayString(keyCode: Int, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyCodeLabel(keyCode)
        return s
    }

    private static func keyCodeLabel(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 43: ",", 44: "/", 45: "N",
            46: "M", 47: ".", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12", 115: "↖", 116: "⇞",
            117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "(\(keyCode))"
    }
}

private func fourCharCode(_ s: String) -> FourCharCode {
    s.unicodeScalars.prefix(4).reduce(FourCharCode(0)) { ($0 << 8) + FourCharCode($1.value) }
}
