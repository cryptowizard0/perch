import Carbon.HIToolbox
import PerchAppCore

/// A system-wide shortcut through Carbon's `RegisterEventHotKey`: works while other apps are frontmost
/// and, unlike an event tap, needs no Accessibility permission.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// nil when the shortcut is taken by another app or cannot be registered.
    init?(_ hotKey: HotKey, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x5052_4348) /* 'PRCH' */, id: 1)
        guard RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
