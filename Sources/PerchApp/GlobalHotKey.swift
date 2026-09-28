import Carbon.HIToolbox
import PerchAppCore

/// A system-wide shortcut through Carbon's `RegisterEventHotKey`: works while other apps are frontmost
/// and, unlike an event tap, needs no Accessibility permission. Each instance has its own id and only reacts
/// to its own key; releasing the instance unregisters it (so shortcuts can come and go with the queue).
final class GlobalHotKey {
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    /// nil when the shortcut is taken by another app or cannot be registered.
    init?(_ hotKey: HotKey, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Every handler sees every hot key; let the others through.
            guard read == noErr, pressed.signature == GlobalHotKey.signature, pressed.id == me.id else {
                return OSStatus(eventNotHandledErr)
            }
            me.action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return nil }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    static let signature = OSType(0x5052_4348)  // 'PRCH'

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
