import Foundation
import AppKit
import Combine
import VeloxCore

struct Event: Identifiable { let id=UUID(); let date=Date(); let text:String }
final class Session: ObservableObject {
    @Published var demo = false { didSet { updateShiftHotkeys() } }
    @Published var running = false
    @Published var trainerReady = false
    @Published var bluetooth = "Bluetooth starts when you scan"
    @Published var network = "Bridge offline"
    @Published var bridgeActive = false { didSet { updateShiftHotkeys() } }
    @Published var devices: [NearbyDevice] = []
    @Published var controllers: [UUID:String] = [:]
    @Published var inputs: [UUID:Date] = [:]
    @Published var metrics = BikeMetrics()
    @Published var gear = 12
    @Published var mode: TrainingMode = .simulation
    @Published var grade = 0.0
    @Published var commandedPower = 0.0
    @Published var events: [Event] = []
    @Published var history: [Double] = Array(repeating:0,count:80)
    @Published var page = "Ride" { didSet { DispatchQueue.main.async { [weak self] in self?.updateShiftHotkeys() } } }
    @Published private(set) var library = RiderStore.load()
    var profile: RiderProfile { library.active }
    var profiles: [RiderProfile] { library.profiles }
    var gearCount: Int { profile.gearCount }
    var calibration: GearingCalibration { profile.calibration }
    var riderMass: Double { profile.weight }
    var canEditRider: Bool { !bridgeActive || demo }
    var drivetrainDescription: String {
        if profile.style == .drivetrain, let step=profile.drivetrain.gear(gear) { return "\(step.label) · \(String(format:"%.2f",step.ratio)):1" }
        return "Even effort · \(gearCount) gears"
    }
    func selectRider(_ id: UUID) {
        guard canEditRider, library.profiles.contains(where:{ $0.id == id }) else { return }
        var next=library;next.selected=id
        do { try RiderStore.save(next);library=next;gear=profile.startingGear;record("Rider: \(profile.name)") }
        catch { record("Could not save rider: \(error.localizedDescription)") }
    }
    func addRider() {
        guard canEditRider,library.profiles.count<12 else { return }
        let p=RiderProfile(name:"Rider \(library.profiles.count+1)")
        var next=library;next.profiles.append(p);next.selected=p.id
        do { try RiderStore.save(next);library=next;gear=profile.startingGear;record("Added \(p.name). Enter their weight and gearing in Preferences.") }
        catch { record(error.localizedDescription) }
    }
    func deleteRider(_ id:UUID) throws {
        guard canEditRider else { throw SetupError.invalid("Stop the bridge before deleting riders.") }
        guard let deleted=library.profiles.first(where:{ $0.id == id }) else { throw SetupError.invalid("This rider no longer exists.") }
        let next=try library.removing(id)
        let changedRider=library.selected != next.selected
        try RiderStore.save(next);library=next
        if changedRider { gear=profile.startingGear }
        record("Deleted rider: \(deleted.name)")
    }
    @Published var keyboardShiftingEnabled:Bool = UserDefaults.standard.object(forKey:"keyboardShiftingEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keyboardShiftingEnabled,forKey:"keyboardShiftingEnabled");updateShiftHotkeys() }
    }
    @Published var shiftShortcutKeys:ShiftShortcutKeys = ShiftShortcutKeys(rawValue:UserDefaults.standard.string(forKey:"shiftShortcutKeys") ?? "") ?? .brackets {
        didSet { UserDefaults.standard.set(shiftShortcutKeys.rawValue,forKey:"shiftShortcutKeys");updateShiftHotkeys() }
    }
    @Published private(set) var shiftHotkeyConflict=false
    @Published private(set) var shiftHotkeysRegistered=false
    @Published private(set) var shiftHotkeyStatus="Start the bridge or demo to enable."
    private let shiftHotkeys=ShiftHotkeys()
    private var workspaceObserver:NSObjectProtocol?
    private var focusObservers:[NSObjectProtocol]=[]
    var canShiftFromKeyboard:Bool { mode == .simulation && (demo || (bridgeActive && trainerReady && running)) }
    private func updateShiftHotkeys() {
        guard keyboardShiftingEnabled,bridgeActive || demo else {
            shiftHotkeys.stop();shiftHotkeysRegistered=false;shiftHotkeyConflict=false
            shiftHotkeyStatus=keyboardShiftingEnabled ? "Start the bridge or demo to enable." : "Disabled."
            return
        }
        guard let front=NSWorkspace.shared.frontmostApplication else {
            shiftHotkeys.stop();shiftHotkeysRegistered=false;shiftHotkeyConflict=false
            shiftHotkeyStatus="Waiting for an active app.";return
        }
        let ours=front.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let editing=NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil || NSApp.keyWindow?.sheetParent != nil || NSApp.keyWindow?.firstResponder is NSTextView
        guard ShiftShortcutScope.allows(executable:front.executableURL?.lastPathComponent ?? "",isVelox:ours,ridePage:page == "Ride",editing:editing) else {
            shiftHotkeys.stop();shiftHotkeysRegistered=false;shiftHotkeyConflict=false
            shiftHotkeyStatus="Active in Zwift or Veloshift’s Ride view. Other apps keep normal typing."
            return
        }
        if let error=shiftHotkeys.activate(shiftShortcutKeys) { shiftHotkeysRegistered=false;shiftHotkeyConflict=true;shiftHotkeyStatus=error }
        else { shiftHotkeysRegistered=true;shiftHotkeyConflict=false;shiftHotkeyStatus="Active in Zwift or Veloshift’s Ride view." }
    }
    func shiftFromKeyboard(_ delta:Int) {
        guard canShiftFromKeyboard else { return }
        guard let front=NSWorkspace.shared.frontmostApplication,
              ShiftShortcutScope.allows(executable:front.executableURL?.lastPathComponent ?? "",isVelox:front.processIdentifier == ProcessInfo.processInfo.processIdentifier,ridePage:page == "Ride",editing:false) else { return }
        if NSApp.isActive {
            guard NSApp.modalWindow == nil,NSApp.keyWindow?.attachedSheet == nil,NSApp.keyWindow?.sheetParent == nil else { return }
            if NSApp.keyWindow?.firstResponder is NSTextView { return }
        }
        shift(delta)
    }
    func saveRider(_ draft: RiderProfile) throws {
        guard canEditRider else { throw SetupError.invalid("Stop the bridge before changing riders or gearing.") }
        let p=try draft.validated()
        guard let index=library.profiles.firstIndex(where:{ $0.id == p.id }) else { throw SetupError.invalid("Select this rider before saving.") }
        var next=library;next.profiles[index]=p
        try RiderStore.save(next);library=next;gear=p.startingGear
        record("Saved \(p.name): \(p.style == .drivetrain ? p.drivetrain.label : "24 even-effort gears")")
    }
    @Published var rightOnly: Bool = UserDefaults.standard.bool(forKey:"rightOnly") { didSet { hardware.rightOnly=rightOnly; UserDefaults.standard.set(rightOnly,forKey:"rightOnly") } }
    private let hardware=Hardware()
    private let trainer=NetworkTrainer()
    private var timer: Timer?
    private var road=RoadModel()
    private var outstanding=false
    private var lastLoadWrite = ProcessInfo.processInfo.systemUptime
    private var lastTelemetry=Date.distantPast
    private var ticks=0
    private var demoStarted=Date()
    init() {
        gear=profile.startingGear
        shiftHotkeys.onShift={ [weak self] in self?.shiftFromKeyboard($0) }
        workspaceObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in self?.updateShiftHotkeys() }
        for name in [NSApplication.didBecomeActiveNotification,NSWindow.didBecomeKeyNotification] {
            focusObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                DispatchQueue.main.async { self?.updateShiftHotkeys() }
            })
        }
        hardware.rightOnly=rightOnly
        hardware.log={ [weak self] in self?.record($0) }
        hardware.onBluetooth={ [weak self] in self?.bluetooth=$0 }
        hardware.onDevices={ [weak self] in self?.devices=$0 }
        hardware.onTrainer={ [weak self] ready in
            guard let self else { return }; self.trainerReady=ready
            if !ready { self.running=false; self.metrics=BikeMetrics(); self.commandedPower=0; self.stopBridge() }
        }
        hardware.onController={ [weak self] id,name,ready in
            if ready { self?.controllers[id]=name } else { self?.controllers[id]=nil; self?.inputs[id]=nil }
        }
        hardware.onMetrics={ [weak self] m in
            guard let self, !self.demo else { return }; self.metrics=m; self.lastTelemetry=Date()
        }
        hardware.onShift={ [weak self] in self?.shift($0) }
        hardware.onInput={ [weak self] id in self?.inputs[id]=Date() }
        trainer.log={ [weak self] in self?.record($0) }
        trainer.state={ [weak self] in self?.network=$0 }
        trainer.onLost={ [weak self] in self?.releaseLoad() }
        trainer.onControl={ [weak self] data,done in self?.handleControl(data,done) }
        timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.tick() }
        record("Welcome to Veloshift. Connect your KICKR v5 to get started.")
    }
    deinit {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
    }
    func record(_ text:String) { events.insert(Event(text:text),at:0); if events.count>200 { events.removeLast() } }
    func scan() { if demo { endDemo() }; hardware.scan(); page="Devices" }
    func connect(_ d:NearbyDevice) { hardware.connect(d.id) }
    func startBridge() {
        guard trainerReady, !demo else { return }; bridgeActive=true; network="Starting bridge…"; trainer.start()
        record("In Zwift, pair Veloshift KICKR v5 for Power Source, Resistance, and Cadence using the network icon.")
    }
    func stopBridge() { trainer.stop(); bridgeActive=false; network="Bridge offline"; releaseLoad() }
    func releaseLoad() {
        running=false; outstanding=false; commandedPower=0; lastLoadWrite=ProcessInfo.processInfo.systemUptime
        if trainerReady && !demo { hardware.command(Data([5,0,0])) }
    }
    func stopAll() { stopBridge(); hardware.disconnectAll(); controllers.removeAll(); metrics=BikeMetrics(); trainerReady=false; demo=false; record("Session stopped") }
    func shift(_ delta:Int) {
        guard mode == .simulation else { record("ERG controls power; shifting resumes in free ride"); return }
        let g = min(gearCount,max(1,gear+delta)); guard g != gear else { return }; gear=g; record("Gear \(g)")
    }
    private func handleControl(_ d:Data, _ done:@escaping(UInt8)->Void) {
        guard trainerReady, !demo, let op=d.first else { done(4); return }
        switch op {
        case 0:
            guard d.count == 1 else { done(3); return }; done(1)
        case 1:
            guard d.count == 1 else { done(3); return }
            releaseLoad(); mode = .simulation; grade=0; road=RoadModel(); done(1)
        case 7:
            guard d.count == 1 else { done(3); return }; running=true; done(1)
        case 8:
            guard d.count == 2, d[1] == 1 || d[1] == 2 else { done(3); return }; releaseLoad(); done(1)
        case 5:
            guard d.count == 3 else { done(3); return }; let watts=Int(Int16(bitPattern:d.u16(1)))
            guard watts >= 0 && watts <= 1000 else { done(3); return }
            // Switch immediately to prevent a pending simulation tick from overwriting ERG.
            mode = .erg; running=true
            hardware.command(d) { [weak self] ok in
                if ok { self?.commandedPower=Double(watts) } else { self?.releaseLoad() }; done(ok ? 1:4)
            }
        case 0x11:
            guard d.count == 7 else { done(3); return }
            road.wind=Double(Int16(bitPattern:d.u16(1)))/1000
            grade=Double(Int16(bitPattern:d.u16(3)))/100
            road.rolling=Double(d[5])/10000; road.drag=Double(d[6])/100
            mode = .simulation; running=true; done(1)
        default: done(2)
        }
    }
    func startDemo() {
        stopAll(); demo=true; demoStarted=Date(); gear=profile.startingGear; mode = .simulation; running=true; grade=0; commandedPower=calibration.boundedCruise
        history=(0..<80).map { i -> Double in
            let t=Double(i)
            return calibration.boundedCruise + 3.0 * sin(t * 0.15) + 1.0 * cos(t * 0.8)
        }
        page="Ride"; record("Demo enabled. All readings are simulated; no hardware or network connection is active.")
    }
    func endDemo() { demo=false; running=false; metrics=BikeMetrics(); history=Array(repeating:0,count:80); grade=0; commandedPower=0 }
    private func tick() {
        ticks += 1
        if demo {
            let t=Date().timeIntervalSince(demoStarted)
            let cadence = 90 + 2 * sin(t * 0.5)
            let preview=profile.roadModel(grade:grade,gear:gear)
            commandedPower=LoadRamp.next(current:commandedPower,desired:preview.target(cadence:cadence),elapsed:0.25)
            let speed = cadence / 60 * preview.ratio * preview.wheelCircumference * 3.6
            metrics=BikeMetrics(power:commandedPower,cadence:cadence,speed:speed)
        } else if trainerReady && Date().timeIntervalSince(lastTelemetry)>4 {
            metrics=BikeMetrics()
            if running { releaseLoad(); record("Trainer telemetry is stale. Load released; re-pair Resistance in Zwift to resume.") }
        }
        if ticks % 4 == 0 {
            history.append(metrics.power); if history.count>80 { history.removeFirst() }
            if bridgeActive { trainer.publish(metrics) }
        }
        guard running, !demo, trainerReady, mode == .simulation, !outstanding, Date().timeIntervalSince(lastTelemetry)<4 else { return }
        let model=profile.roadModel(grade:grade,wind:road.wind,rolling:road.rolling,drag:road.drag,gear:gear)
        let requested = model.target(cadence:metrics.cadence)
        let now = ProcessInfo.processInfo.systemUptime
        let target = LoadRamp.next(current:commandedPower,desired:requested,elapsed:now-lastLoadWrite)
        guard Int(target.rounded()) != Int(commandedPower.rounded()) else { return }
        lastLoadWrite=now
        var packet=Data([5]); packet.le16(UInt16(clamping:Int(target.rounded())))
        outstanding=true
        hardware.command(packet) { [weak self] ok in
            guard let self else { return }; self.outstanding=false
            if ok, self.mode == .simulation, self.running { self.commandedPower=target.rounded() }
        }
    }
    func exportDiagnostics() {
        let panel=NSSavePanel(); panel.nameFieldStringValue="Veloshift-diagnostics.txt"; panel.allowedContentTypes=[.plainText]
        guard panel.runModal() == .OK, let url=panel.url else { return }
        let text="Veloshift 0.6 • macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\(bluetooth)\n\(network)\n\n" + events.reversed().map { "\($0.date.ISO8601Format()) \($0.text)" }.joined(separator:"\n")
        do { try text.write(to:url,atomically:true,encoding:.utf8) } catch { record("Could not save diagnostics: \(error.localizedDescription)") }
    }
}
