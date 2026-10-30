import AppKit
import Carbon
import VeloxCore

/// Registers only two explicit global hotkeys; no event taps or keyboard monitoring.
final class ShiftHotkeys {
    var onShift:(Int)->Void = { _ in }
    private var handler:EventHandlerRef?
    private var up:EventHotKeyRef?
    private var down:EventHotKeyRef?
    private var chord:ShiftShortcutKeys?
    private var presses=ShiftKeyPresses()
    private static let signature:OSType=0x564C4F58 // VLOX

    /// nil means both keys are registered; otherwise neither remains registered.
    func activate(_ requested:ShiftShortcutKeys) -> String? {
        if chord == requested, up != nil, down != nil { return nil }
        stop()
        var types=[EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        let status=InstallEventHandler(GetApplicationEventTarget(), { _,event,context in
            guard let event,let context else { return OSStatus(eventNotHandledErr) }
            let owner=Unmanaged<ShiftHotkeys>.fromOpaque(context).takeUnretainedValue()
            return owner.handle(event)
        },types.count,&types,Unmanaged.passUnretained(self).toOpaque(),&handler)
        guard status == noErr else { stop();return failure(status) }
        let harderCode=requested == .brackets ? UInt32(kVK_ANSI_RightBracket) : UInt32(kVK_ANSI_K)
        let easierCode=requested == .brackets ? UInt32(kVK_ANSI_LeftBracket) : UInt32(kVK_ANSI_J)
        let first=RegisterEventHotKey(harderCode,0,EventHotKeyID(signature:Self.signature,id:1),GetApplicationEventTarget(),UInt32(kEventHotKeyExclusive),&up)
        guard first == noErr else { stop();return failure(first) }
        let second=RegisterEventHotKey(easierCode,0,EventHotKeyID(signature:Self.signature,id:2),GetApplicationEventTarget(),UInt32(kEventHotKeyExclusive),&down)
        guard second == noErr else { stop();return failure(second) }
        chord=requested;return nil
    }
    private func failure(_ status:OSStatus)->String { "Shortcut unavailable (macOS \(status)). Try the other key pair." }
    private func handle(_ event:EventRef)->OSStatus {
        var id=EventHotKeyID()
        let result=GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
        guard result == noErr,id.signature == Self.signature,id.id == 1 || id.id == 2 else { return OSStatus(eventNotHandledErr) }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { presses.release(id.id) }
        else if let delta=presses.press(id.id) { onShift(delta) }
        return noErr
    }
    func stop() {
        if let up { UnregisterEventHotKey(up) };up=nil
        if let down { UnregisterEventHotKey(down) };down=nil
        if let handler { RemoveEventHandler(handler) };handler=nil
        chord=nil;presses.reset()
    }
    deinit { stop() }
}
