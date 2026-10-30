import Foundation

public enum SetupError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public struct VirtualGear: Equatable, Identifiable {
    public let id: Int
    public let chainring: Int
    public let sprocket: Int
    public var ratio: Double { Double(chainring) / Double(sprocket) }
    public var label: String { "\(chainring)×\(sprocket)" }
}
public struct Drivetrain: Codable, Equatable {
    public var chainrings: [Int]
    public var cassette: [Int]
    public var circumference: Double
    public init(chainrings: [Int] = [48,35], cassette: [Int] = Self.sram1036, circumference: Double = 2.105) {
        self.chainrings=chainrings; self.cassette=cassette; self.circumference=circumference
    }
    public static let sram1036 = [10,11,12,13,15,17,19,21,24,28,32,36]
    public func validated() throws -> Self {
        guard (1...2).contains(chainrings.count), chainrings.allSatisfy({ (20...80).contains($0) }), Set(chainrings).count == chainrings.count else { throw SetupError.invalid("Enter one or two different chainrings, each from 20 to 80 teeth.") }
        guard (1...24).contains(cassette.count), cassette.allSatisfy({ (5...100).contains($0) }), Set(cassette).count == cassette.count else { throw SetupError.invalid("Enter 1–24 different sprockets, each from 5 to 100 teeth.") }
        guard circumference.isFinite, (1...3).contains(circumference) else { throw SetupError.invalid("Wheel circumference must be between 1,000 and 3,000 mm.") }
        return Self(chainrings:chainrings.sorted(by:>),cassette:cassette.sorted(),circumference:circumference)
    }
    public var gears: [VirtualGear] {
        guard let valid=try? validated() else { return [] }
        let pairs=valid.chainrings.flatMap { front in valid.cassette.map { rear in (front,rear) } }.sorted { a,b in
            // Integer comparison preserves exact ordering, including identical ratios.
            if a.0*b.1 != b.0*a.1 { return a.0*b.1 < b.0*a.1 }
            return a.0 == b.0 ? a.1 < b.1 : a.0 < b.0
        }
        return pairs.enumerated().map { VirtualGear(id:$0.offset+1,chainring:$0.element.0,sprocket:$0.element.1) }
    }
    public func gear(_ index: Int) -> VirtualGear? {
        let table=gears; guard !table.isEmpty else { return nil }; return table[min(table.count,max(1,index))-1]
    }
    public var label: String { "\(chainrings.count)×\(cassette.count) · \(gears.count) gears" }
    public static func parseTeeth(_ text: String) throws -> [Int] {
        let tokens=text.components(separatedBy:CharacterSet(charactersIn:",;/ ").union(.whitespacesAndNewlines)).filter { !$0.isEmpty }
        guard !tokens.isEmpty, tokens.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) && Int($0) != nil }) else { throw SetupError.invalid("Enter whole tooth counts separated by commas. A range such as 10–36 needs the full sprocket list or the generator.") }
        return tokens.compactMap(Int.init)
    }
    /// Generates an approximation only. A range and count cannot identify an actual cassette.
    public static func approximateCassette(speeds:Int, smallest:Int, largest:Int) throws -> [Int] {
        guard (1...24).contains(speeds), (5...100).contains(smallest), (smallest...100).contains(largest), largest-smallest >= speeds-1 else { throw SetupError.invalid("The sprocket range must contain enough different whole tooth counts for the requested rear speeds.") }
        guard speeds>1 else { return [smallest] }
        var result=[smallest]
        for index in 1..<speeds {
            let fraction=Double(index)/Double(speeds-1)
            let ideal=Int((Double(smallest)*pow(Double(largest)/Double(smallest),fraction)).rounded())
            let remaining=speeds-1-index
            result.append(min(largest-remaining,max(result.last!+1,ideal)))
        }
        return result
    }
}
public enum GearingStyle: String, Codable, CaseIterable { case evenEffort, drivetrain
    public var label: String { self == .evenEffort ? "Even effort" : "Match a bike" }
}
public struct RiderProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var weight: Double
    public var style: GearingStyle
    public var cruiseWatts: Double
    public var stepFraction: Double
    public var drivetrain: Drivetrain
    public var loadScale: Double
    public init(id:UUID = UUID(),name:String = "Rider 1",weight:Double = 75,style:GearingStyle = .evenEffort,cruiseWatts:Double = 150,stepFraction:Double = 0.06,drivetrain:Drivetrain = Drivetrain(),loadScale:Double = 1) {
        self.id=id;self.name=name;self.weight=weight;self.style=style;self.cruiseWatts=cruiseWatts;self.stepFraction=stepFraction;self.drivetrain=drivetrain;self.loadScale=loadScale
    }
    public var gearCount: Int { style == .evenEffort ? 24 : drivetrain.gears.count }
    public var startingGear: Int { max(1,(gearCount+1)/2) }
    public var calibration: GearingCalibration { GearingCalibration(cruiseWatts:cruiseWatts,stepFraction:stepFraction) }
    public func validated() throws -> Self {
        var p=self;p.name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (1...60).contains(p.name.count) else { throw SetupError.invalid("Give the rider a name of 1–60 characters.") }
        guard weight.isFinite, (30...200).contains(weight) else { throw SetupError.invalid("Rider weight must be between 30 and 200 kg.") }
        guard cruiseWatts.isFinite,(75...400).contains(cruiseWatts),stepFraction.isFinite,(0.03...0.08).contains(stepFraction) else { throw SetupError.invalid("Cruising effort must be 75–400 W and spacing 3–8%.") }
        guard loadScale.isFinite,(0.25...1).contains(loadScale) else { throw SetupError.invalid("Road load must be between 25% and 100%.") }
        p.drivetrain=try drivetrain.validated();return p
    }
    public func roadModel(grade:Double = 0,wind:Double = 0,rolling:Double = 0.004,drag:Double = 0.51,gear:Int) -> RoadModel {
        var road=RoadModel();road.riderMass=weight;road.calibration=calibration;road.gear=gear
        road.grade=grade;road.wind=wind;road.rolling=rolling;road.drag=drag
        if style == .drivetrain {
            road.virtualRatio=drivetrain.gear(gear)?.ratio
            road.wheelCircumference=drivetrain.circumference
            road.loadScale=loadScale
        }
        return road
    }
}
public struct RiderLibrary: Codable, Equatable {
    public var profiles: [RiderProfile]
    public var selected: UUID
    public init(profiles:[RiderProfile],selected:UUID) { self.profiles=profiles;self.selected=selected }
    public var active: RiderProfile { profiles.first(where:{ $0.id == selected }) ?? profiles[0] }
    public func removing(_ id:UUID) throws -> Self {
        let original=try validated()
        guard let index=original.profiles.firstIndex(where:{ $0.id == id }) else { throw SetupError.invalid("This rider no longer exists.") }
        guard original.profiles.count>1 else { throw SetupError.invalid("Keep at least one rider profile.") }
        var next=original;next.profiles.remove(at:index)
        if original.selected == id { next.selected=next.profiles[min(index,next.profiles.count-1)].id }
        return try next.validated()
    }
    public func validated() throws -> Self {
        guard (1...12).contains(profiles.count),Set(profiles.map(\.id)).count == profiles.count,profiles.contains(where:{ $0.id == selected }) else { throw SetupError.invalid("Invalid rider library.") }
        return try Self(profiles:profiles.map { try $0.validated() },selected:selected)
    }
}
public enum RiderStore {
    public static let key="riderLibrary.v1"
    public static func load(_ defaults:UserDefaults = .standard) -> RiderLibrary {
        if let data=defaults.data(forKey:key),let decoded=try? JSONDecoder().decode(RiderLibrary.self,from:data),let valid=try? decoded.validated() { return valid }
        // Preserve the existing working even-effort calibration when upgrading 0.2.
        var p=RiderProfile()
        if let w=defaults.object(forKey:"riderMass") as? Double,w.isFinite { p.weight=min(200,max(30,w)) }
        let calibration=GearingCalibration(cruiseWatts:defaults.object(forKey:"cruiseWatts") as? Double ?? 150,stepFraction:defaults.object(forKey:"gearStep") as? Double ?? 0.06)
        p.cruiseWatts=calibration.boundedCruise;p.stepFraction=calibration.boundedStep
        return RiderLibrary(profiles:[p],selected:p.id)
    }
    public static func save(_ library:RiderLibrary,_ defaults:UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(library.validated()),forKey:key)
    }
}
