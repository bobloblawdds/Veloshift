import Foundation

public enum ShiftShortcutKeys: String, Codable, CaseIterable, Identifiable {
    case brackets
    case jk
    public var id:String { rawValue }
    public var label:String { self == .brackets ? "Brackets [ / ]" : "Letters J / K" }
    public var easier:String { self == .brackets ? "[" : "J" }
    public var harder:String { self == .brackets ? "]" : "K" }
}
public enum ShiftShortcutScope {
    public static func allows(executable:String,isVelox:Bool,ridePage:Bool,editing:Bool) -> Bool {
        if isVelox { return ridePage && !editing }
        return executable == "ZwiftAppSilicon" || executable == "ZwiftApp"
    }
}

/// Carbon can emit repeated pressed events while a key is held.
/// Only a new down/up cycle should produce another shift.
public struct ShiftKeyPresses {
    private var held=Set<UInt32>()
    public init() {}
    public mutating func press(_ id:UInt32) -> Int? {
        guard id == 1 || id == 2 else { return nil }
        guard held.insert(id).inserted else { return nil }
        return id == 1 ? 1 : -1
    }
    public mutating func release(_ id:UInt32) { held.remove(id) }
    public mutating func reset() { held.removeAll() }
}
