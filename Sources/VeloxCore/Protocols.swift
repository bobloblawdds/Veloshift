import Foundation

public extension Data {
    mutating func le16(_ n: UInt16) { append(UInt8(truncatingIfNeeded: n)); append(UInt8(truncatingIfNeeded: n >> 8)) }
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i+1]) << 8 }
}

public struct BikeMetrics: Equatable {
    public var power: Double = 0
    public var cadence: Double = 0
    public var speed: Double = 0 // km/h, actual trainer speed
    public init(power: Double = 0, cadence: Double = 0, speed: Double = 0) { self.power = power; self.cadence = cadence; self.speed = speed }
    public var packet: Data {
        var d = Data(); d.le16(0x44); d.le16(UInt16(clamping: Int(max(0, speed) * 100)))
        d.le16(UInt16(clamping: Int(max(0, cadence) * 2))); d.le16(UInt16(clamping: Int(max(0, power))))
        return d
    }
    /// Decode optional fields in FTMS order; malformed packets never partially update state.
    public static func decode(_ data: Data, previous: BikeMetrics = BikeMetrics()) -> BikeMetrics? {
        let d = Data(data); guard d.count >= 2 else { return nil }
        let f = d.u16(0); var p = 2; var m = previous
        func take(_ size: Int) -> Bool { guard p + size <= d.count else { return false }; p += size; return true }
        if f & 1 == 0 { guard take(2) else { return nil }; m.speed = Double(d.u16(p-2))/100 }
        if f & 2 != 0 { guard take(2) else { return nil } }
        if f & 4 != 0 { guard take(2) else { return nil }; m.cadence = Double(d.u16(p-2))/2 }
        if f & 8 != 0 { guard take(2) else { return nil } }
        if f & 16 != 0 { guard take(3) else { return nil } }
        if f & 32 != 0 { guard take(2) else { return nil } }
        if f & 64 != 0 { guard take(2) else { return nil }; m.power = Double(Int16(bitPattern: d.u16(p-2))) }
        for (bit, size) in [(7,2),(8,5),(9,1),(10,1),(11,2),(12,2)] where f & (1 << bit) != 0 { guard take(size) else { return nil } }
        return m
    }
}

public enum TrainingMode: String { case simulation = "Free ride", erg = "ERG workout" }
/// The flat-road effort table is linear in watts at the reference cadence.
/// Gear ratios are then solved from the road physics, rather than spaced exponentially.
public struct GearingCalibration {
    public var cruiseWatts = 150.0
    public var stepFraction = 0.06
    public static let referenceCadence = 90.0
    public init(cruiseWatts: Double = 150, stepFraction: Double = 0.06) {
        self.cruiseWatts = cruiseWatts; self.stepFraction = stepFraction
    }
    public var boundedCruise: Double { min(400, max(75, cruiseWatts.isFinite ? cruiseWatts : 150)) }
    public var boundedStep: Double { min(0.08, max(0.03, stepFraction.isFinite ? stepFraction : 0.06)) }
    public func referencePower(gear: Int) -> Double {
        boundedCruise * (1 + Double(min(24, max(1, gear)) - 12) * boundedStep)
    }
    public func ratio(gear: Int, totalMass: Double, circumference: Double) -> Double {
        let watts = referencePower(gear: gear)
        let mass = min(250, max(30, totalMass.isFinite ? totalMass : 84))
        let wheel = min(3, max(1, circumference.isFinite ? circumference : 2.105))
        // Fixed reference road: level, no wind, Crr .004, CdA .51 m².
        // Bisection inverts the monotonic a*v + b*v³ power curve.
        var low = 0.0, high = 30.0
        for _ in 0..<48 {
            let speed = (low + high) / 2
            let load = mass * 9.80665 * 0.004 * speed + 0.5 * 1.225 * 0.51 * pow(speed, 3)
            if load < watts { low = speed } else { high = speed }
        }
        return (low + high) / 2 / (Self.referenceCadence / 60 * wheel)
    }
}

/// Smooth load changes in real time; releasing load bypasses the filter.
public enum LoadRamp {
    public static func next(current: Double, desired: Double, elapsed: Double) -> Double {
        guard desired.isFinite, desired > 0 else { return 0 }
        let target = min(1000, desired)
        let previous = min(1000, max(0, current.isFinite ? current : 0))
        let dt = min(0.5, max(0, elapsed.isFinite ? elapsed : 0))
        guard dt > 0 else { return previous }
        let difference = target - previous
        let filtered = abs(difference) < 2 ? difference : difference * (1 - exp(-dt / 0.55))
        return previous + min(60 * dt, max(-90 * dt, filtered))
    }
}

public struct RoadModel {
    public var virtualRatio: Double? = nil
    public var loadScale = 1.0
    public var calibration = GearingCalibration()
    public var riderMass = 75.0
    public var bikeMass = 9.0
    public var wheelCircumference = 2.105
    public var gear = 12
    public var grade = 0.0
    public var wind = 0.0
    public var rolling = 0.004
    public var drag = 0.51
    public var maxPower = 1000.0
    public init() {}
    public var ratio: Double {
        if let virtualRatio, virtualRatio.isFinite, virtualRatio > 0 { return virtualRatio }
        return calibration.ratio(gear: gear, totalMass: riderMass + bikeMass, circumference: wheelCircumference)
    }
    /// Experimental cadence-based road-load model. Sends ERG targets to legacy hardware.
    /// Measured power is always passed through to Zwift unchanged.
    public func target(cadence: Double) -> Double { min(maxPower, requiredPower(cadence:cadence)) }
    public func requiredPower(cadence: Double) -> Double {
        guard cadence.isFinite, cadence >= 20 else { return 0 }
        let v = max(0, cadence) / 60 * ratio * wheelCircumference
        let theta = atan(grade / 100)
        let gravity = (riderMass + bikeMass) * 9.80665 * (sin(theta) + rolling * cos(theta))
        let air = v + wind
        let force = gravity + 0.5 * 1.225 * drag * air * abs(air)
        return max(0, force * v * min(1,max(0.25,loadScale)))
    }
}

/// Small bounded protobuf reader for Click 2's active-low button-map field.
public enum Proto {
    public static func varint(_ d: Data, _ p: inout Int) -> UInt64? {
        var n: UInt64 = 0
        for s in stride(from: 0, through: 63, by: 7) {
            guard p < d.count else { return nil }; let b = d[p]; p += 1
            if s == 63 && b > 1 { return nil }
            n |= UInt64(b & 127) << s
            if b < 128 { return n }
        }
        return nil
    }
    public static func field(_ number: UInt64, in d: Data) -> UInt64? {
        var p = 0
        while p < d.count {
            guard let key = varint(d, &p), key >> 3 > 0 else { return nil }
            switch key & 7 {
            case 0: guard let v = varint(d, &p) else { return nil }; if key >> 3 == number { return v }
            case 1: p += 8
            case 2: guard let n = varint(d, &p), n <= UInt64(d.count - p) else { return nil }; p += Int(n)
            case 5: p += 4
            default: return nil
            }
            if p > d.count { return nil }
        }
        return nil
    }
}
public struct ClickDecoder {
    private var previous: UInt32 = .max
    public init() {}
    public mutating func reset() { previous = .max }
    public mutating func shifts(_ packet: Data, rightOnly: Bool) -> [Int] {
        guard packet.first == 0x23, let value = Proto.field(1, in: Data(packet.dropFirst())), value <= UInt32.max else { return [] }
        let bits = UInt32(value); let pressed = previous & ~bits; previous = bits
        var result: [Int] = []
        if pressed & 0x1000 != 0 { result.append(1) }
        if rightOnly { if pressed & 0x20 != 0 { result.append(-1) } }
        else if pressed & 0x100 != 0 { result.append(-1) }
        return result
    }
}

public struct DirConFrame: Equatable {
    public var id: UInt8
    public var sequence: UInt8
    public var status: UInt8
    public var body: Data
    public init(id: UInt8, sequence: UInt8 = 0, status: UInt8 = 0, body: Data = Data()) { self.id=id; self.sequence=sequence; self.status=status; self.body=body }
    public var encoded: Data {
        var d = Data([1,id,sequence,status,UInt8(truncatingIfNeeded: body.count >> 8),UInt8(truncatingIfNeeded: body.count)])
        d.append(body); return d
    }
    public static func extract(from buffer: inout Data) throws -> DirConFrame? {
        guard buffer.count >= 6 else { return nil }
        guard buffer[0] == 1 else { throw ParseError.version }
        let length = Int(buffer[4]) << 8 | Int(buffer[5]); guard length <= 4096 else { throw ParseError.length }
        guard buffer.count >= 6 + length else { return nil }
        let frame = DirConFrame(id:buffer[1],sequence:buffer[2],status:buffer[3],body:Data(buffer[6..<(6+length)]))
        buffer = Data(buffer.dropFirst(6+length)); return frame
    }
    public enum ParseError: Error { case version, length }
}
public enum GATT {
    public static func uuid(_ short: String) -> Data {
        let s = "0000\(short)-0000-1000-8000-00805F9B34FB".replacingOccurrences(of: "-", with: "")
        return Data(stride(from:0,to:s.count,by:2).map { i in UInt8(s.dropFirst(i).prefix(2),radix:16)! })
    }
    public static let service = uuid("1826"), feature = uuid("2ACC"), bike = uuid("2AD2"), control = uuid("2AD9"), status = uuid("2ADA"), powerRange = uuid("2AD8")
    public static let chars: [(Data,UInt8)] = [(feature,1),(bike,4),(control,6),(status,4),(powerRange,1)]
    // cadence + power; power target + indoor bike simulation supported
    public static let features = Data([2,64,0,0,8,32,0,0])
    public static let range = Data([0,0,0xE8,3,1,0]) // 0...1000 W, increment 1
}
