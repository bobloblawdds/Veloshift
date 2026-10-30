import Foundation
var failures = 0
func fail(_ text:String, file:StaticString = #filePath,line:UInt = #line) { failures += 1; print("FAIL \(file):\(line): \(text)") }
func expectEqual<T:Equatable>(_ a:@autoclosure () throws->T,_ b:T,file:StaticString = #filePath,line:UInt = #line) { do { let v=try a(); if v != b { fail("\(v) != \(b)",file:file,line:line) } } catch { fail("\(error)",file:file,line:line) } }
func expectNil<T>(_ a:T?,file:StaticString = #filePath,line:UInt = #line) { if a != nil { fail("Expected nil",file:file,line:line) } }
func expectTrue(_ a:Bool,file:StaticString = #filePath,line:UInt = #line) { if !a { fail("Expected true",file:file,line:line) } }
func expectGreater<T:Comparable>(_ a:T,_ b:T,file:StaticString = #filePath,line:UInt = #line) { if a <= b { fail("Expected greater",file:file,line:line) } }
func expectAtMost<T:Comparable>(_ a:T,_ b:T,file:StaticString = #filePath,line:UInt = #line) { if a > b { fail("Expected at most",file:file,line:line) } }
func expectThrows<T>(_ a:@autoclosure () throws ->T,file:StaticString = #filePath,line:UInt = #line) { do { _=try a(); fail("Expected throw",file:file,line:line) } catch {} }
final class Expectation {
 let description:String; var fulfilled=false
 init(description:String) { self.description=description }
 func fulfill() { fulfilled=true }
}
func wait(for expectations:[Expectation],timeout:TimeInterval) {
 let end=Date().addingTimeInterval(timeout)
 while !expectations.allSatisfy({ $0.fulfilled }) && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
 for e in expectations where !e.fulfilled { fail("Timeout: \(e.description)") }
}
import Foundation
import Network
import VeloxCore

final class ProtocolTests {
    func testTelemetryRoundTrip() {
        let m=BikeMetrics(power:284,cadence:91.5,speed:32.71)
        expectEqual(BikeMetrics.decode(m.packet),m)
        expectEqual(m.packet,Data([0x44,0,0xC7,0x0C,0xB7,0,0x1C,1]))
    }
    func testTruncatedOptionalFieldsAreRejected() {
        let d=BikeMetrics(power:200,cadence:90,speed:30).packet
        for i in 0..<d.count { expectNil(BikeMetrics.decode(Data(d.prefix(i)))) }
        expectNil(BikeMetrics.decode(Data([0x44,1,0,0,0,0,0,0]))) // energy flag requires 5 bytes
    }
    func testMoreDataPreservesSpeed() {
        expectEqual(BikeMetrics.decode(Data([0x41,0,0xFA,0]),previous:BikeMetrics(speed:30)),BikeMetrics(power:250,speed:30))
    }
    func testSignedPower() { expectEqual(BikeMetrics.decode(Data([0x40,0,0,0,0xFF,0xFF]))?.power,-1) }
    func testGearsAndRoadLoad() {
        var road=RoadModel(); road.gear=1; let easy=road.target(cadence:90)
        road.gear=24; expectGreater(road.target(cadence:90),easy)
        let flat=road.target(cadence:90); road.grade=10; expectGreater(road.target(cadence:90),flat)
        expectEqual(road.target(cadence:0),0); expectEqual(road.target(cadence:19),0)
        road.grade=100; expectAtMost(road.target(cadence:200),1000)
        road.grade = -25; expectEqual(road.target(cadence:40),0)
    }
    func testEvenGearingAtReferenceCadence() {
        var road=RoadModel()
        let expected=[51.0,60,69,78,87,96,105,114,123,132,141,150,159,168,177,186,195,204,213,222,231,240,249,258]
        var previous=0.0
        for gear in 1...24 {
            road.gear=gear
            let watts=road.target(cadence:90)
            expectAtMost(abs(watts-expected[gear-1]),0.000001)
            if gear>1 { expectAtMost(abs(watts-previous-9),0.000001) }
            previous=watts
        }
        // Inversion remains calibrated when rider mass changes.
        for mass in [45.0,75,120] {
            road.riderMass=mass;road.gear=12
            expectAtMost(abs(road.target(cadence:90)-150),0.000001)
        }
    }
    func testGearTuningAndCadenceResponse() {
        var road=RoadModel()
        road.calibration=GearingCalibration(cruiseWatts:250,stepFraction:0.04)
        road.gear=12;expectAtMost(abs(road.target(cadence:90)-250),0.000001)
        road.gear=13;expectAtMost(abs(road.target(cadence:90)-260),0.000001)
        for cadence in [60.0,75,90,105] {
            for slope in [0.0,3,6] {
                road.grade=slope
                var previous=0.0
                for gear in 1...24 {
                    road.gear=gear
                    let watts=road.target(cadence:cadence)
                    expectTrue(watts>=previous);expectAtMost(watts,1000);previous=watts
                }
            }
        }
        road.grade=0;road.gear=12
        expectGreater(road.target(cadence:100),road.target(cadence:80))
    }
    func testCalibrationBoundsKeepAll24GearsDistinct() {
        for cruise in [75.0,150,400] {
            for step in [0.03,0.06,0.08] {
                let c=GearingCalibration(cruiseWatts:cruise,stepFraction:step)
                var previous=0.0
                for g in 1...24 {
                    let w=c.referencePower(gear:g);expectGreater(w,previous);expectAtMost(w,1000);previous=w
                }
            }
        }
        let invalid=GearingCalibration(cruiseWatts:.nan,stepFraction:.infinity)
        expectEqual(invalid.referencePower(gear:12),150)
        expectEqual(invalid.referencePower(gear:0),invalid.referencePower(gear:1))
        expectEqual(invalid.referencePower(gear:25),invalid.referencePower(gear:24))
    }
    func testLoadSmoothingRateSettlingAndRelease() {
        let initial=LoadRamp.next(current:150,desired:159,elapsed:0.25)
        expectGreater(initial,150);expectTrue(initial<159)
        var current=150.0
        for _ in 0..<12 { current=LoadRamp.next(current:current,desired:159,elapsed:0.25) }
        expectEqual(current,159)
        expectAtMost(LoadRamp.next(current:100,desired:800,elapsed:0.25),115)
        expectGreater(LoadRamp.next(current:400,desired:100,elapsed:0.25),377)
        expectEqual(LoadRamp.next(current:800,desired:0,elapsed:0.01),0)
        expectEqual(LoadRamp.next(current:150,desired:250,elapsed:0),150)
        expectEqual(LoadRamp.next(current:150,desired:.nan,elapsed:0.25),0)
        expectAtMost(LoadRamp.next(current:100,desired:800,elapsed:60),130)
    }
    func testOneByTwelveAndThirteen() throws {
        let twelve=try Drivetrain(chainrings:[48],cassette:Drivetrain.sram1036).validated()
        expectEqual(twelve.gears.count,12)
        expectEqual(twelve.gears.first?.label,"48×36");expectEqual(twelve.gears.last?.label,"48×10")
        let rear=try Drivetrain.approximateCassette(speeds:13,smallest:10,largest:46)
        let thirteen=try Drivetrain(chainrings:[40],cassette:rear).validated()
        expectEqual(thirteen.gears.count,13);expectEqual(thirteen.gears.last?.ratio,4)
        expectEqual(thirteen.gears.map(\.id),Array(1...13))
    }
    func testSramTwoByTwelveOrdering() throws {
        let drivetrain=try Drivetrain().validated();let table=drivetrain.gears
        expectEqual(table.count,24);expectEqual(table.first?.label,"35×36");expectEqual(table.last?.label,"48×10")
        expectEqual(Set(table.map(\.label)).count,24)
        for i in 1..<table.count { expectTrue(table[i].ratio>=table[i-1].ratio) }
        expectEqual(drivetrain.gear(0),table.first);expectEqual(drivetrain.gear(100),table.last)
        // Preserve identical ratios: 24 combinations means all combinations.
        let overlap=Drivetrain(chainrings:[48,32],cassette:[12,18])
        expectEqual(overlap.gears.count,4)
        expectEqual(overlap.gears[1].ratio,overlap.gears[2].ratio)
    }
    func testDrivetrainValidationAndParsing() throws {
        expectEqual(try Drivetrain.parseTeeth("48/35"),[48,35])
        expectEqual(try Drivetrain.parseTeeth("10, 11;12 13"),[10,11,12,13])
        for text in ["10-36","48.5","-10","","10,garbage","999999999999999999999"] { expectThrows(try Drivetrain.parseTeeth(text)) }
        expectThrows(try Drivetrain(chainrings:[],cassette:[10,12]).validated())
        expectThrows(try Drivetrain(chainrings:[48,48],cassette:[10,12]).validated())
        expectThrows(try Drivetrain(chainrings:[48],cassette:[10,10]).validated())
        expectThrows(try Drivetrain(chainrings:[48],cassette:[0,12]).validated())
        expectThrows(try Drivetrain(circumference:.nan).validated())
        expectTrue(Drivetrain(chainrings:[],cassette:[]).gears.isEmpty)
    }
    func testCassetteGeneratorBoundsAndUniqueness() throws {
        for count in 1...24 {
            let teeth=try Drivetrain.approximateCassette(speeds:count,smallest:10,largest:46)
            expectEqual(teeth.count,count);expectEqual(Set(teeth).count,count);expectEqual(teeth.first,10)
            if count>1 { expectEqual(teeth.last,46) }
            expectEqual(teeth,teeth.sorted())
        }
        expectThrows(try Drivetrain.approximateCassette(speeds:13,smallest:10,largest:15))
        expectThrows(try Drivetrain.approximateCassette(speeds:0,smallest:10,largest:36))
        expectThrows(try Drivetrain.approximateCassette(speeds:12,smallest:120,largest:130))
    }
    func testExactRatioRoadPowerAndCommandCap() {
        let p=RiderProfile(style:.drivetrain)
        let road=p.roadModel(gear:24)
        expectEqual(road.ratio,4.8)
        let speed=100.0/60*road.ratio*road.wheelCircumference*3.6
        expectAtMost(abs(speed-60.624),0.00001)
        expectAtMost(abs(road.requiredPower(cadence:100)-1547.260651608),0.00001)
        expectEqual(road.target(cadence:100),1000)
        expectEqual(p.roadModel(gear:1).ratio,35.0/36)
        var assisted=p;assisted.loadScale=0.25
        expectAtMost(abs(assisted.roadModel(gear:24).target(cadence:100)-386.815162902),0.00001)
        expectEqual(assisted.roadModel(gear:24).ratio,4.8)
        expectEqual(road.target(cadence:0),0)
    }
    func testRiderProfilesRemainIndependent() throws {
        let a=RiderProfile(name:"Rider A",weight:80,style:.drivetrain)
        let b=RiderProfile(name:"Rider B",weight:60,cruiseWatts:100)
        let library=try RiderLibrary(profiles:[a,b],selected:b.id).validated()
        expectEqual(library.active,b);expectEqual(library.profiles[0],a)
        expectEqual(a.gearCount,24);expectEqual(b.calibration.boundedCruise,100)
        let single=RiderProfile(style:.drivetrain,drivetrain:Drivetrain(chainrings:[40],cassette:Array(10...22)))
        expectEqual(single.gearCount,13);expectEqual(single.startingGear,7)
        expectGreater(a.roadModel(grade:5,gear:12).target(cadence:90),RiderProfile(weight:60,style:.drivetrain).roadModel(grade:5,gear:12).target(cadence:90))
        expectThrows(try RiderProfile(name:"  ").validated())
        expectThrows(try RiderProfile(weight:.nan).validated())
        expectThrows(try RiderLibrary(profiles:[],selected:UUID()).validated())
        expectThrows(try RiderLibrary(profiles:[a,a],selected:a.id).validated())
    }
    func testRiderPersistenceAndMigration() throws {
        let suite="VeloxChecks."+UUID().uuidString
        guard let defaults=UserDefaults(suiteName:suite) else { fail("No test defaults");return }
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(82.0,forKey:"riderMass");defaults.set(175.0,forKey:"cruiseWatts");defaults.set(0.05,forKey:"gearStep")
        let migrated=RiderStore.load(defaults)
        expectEqual(migrated.active.weight,82);expectEqual(migrated.active.cruiseWatts,175);expectEqual(migrated.active.style,.evenEffort)
        let second=RiderProfile(name:"Second",weight:65,style:.drivetrain,loadScale:0.5)
        let saved=RiderLibrary(profiles:migrated.profiles+[second],selected:second.id)
        try RiderStore.save(saved,defaults)
        let checked=try saved.validated();expectEqual(RiderStore.load(defaults),checked)
        defaults.set(Data("invalid JSON".utf8),forKey:RiderStore.key)
        expectEqual(RiderStore.load(defaults).active.cruiseWatts,175)
    }
    func testRiderDeletionSelection() throws {
        let a=RiderProfile(name:"A"),b=RiderProfile(name:"B"),c=RiderProfile(name:"C")
        let original=RiderLibrary(profiles:[a,b,c],selected:b.id)
        let next=try original.removing(b.id)
        expectEqual(next.profiles,[a,c]);expectEqual(next.selected,c.id)
        expectEqual(original.profiles,[a,b,c])
        expectEqual(try original.removing(a.id).selected,b.id)
        let last=RiderLibrary(profiles:[a,b,c],selected:c.id)
        expectEqual(try last.removing(c.id).selected,b.id)
    }
    func testRiderDeletionGuards() throws {
        let a=RiderProfile(name:"Only rider")
        let library=RiderLibrary(profiles:[a],selected:a.id)
        expectThrows(try library.removing(a.id))
        expectThrows(try library.removing(UUID()))
        expectEqual(library.active,a)
    }
    func testRiderDeletionPersists() throws {
        let suite="VeloxDeletionChecks."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let a=RiderProfile(name:"A"),b=RiderProfile(name:"B",weight:60)
        let original=RiderLibrary(profiles:[a,b],selected:a.id)
        try RiderStore.save(original,defaults)
        let next=try RiderStore.load(defaults).removing(a.id)
        try RiderStore.save(next,defaults)
        expectEqual(RiderStore.load(defaults),next)
        expectEqual(RiderStore.load(defaults).profiles,[b])
    }
    func testKeyboardPressEdges() {
        var keys=ShiftKeyPresses()
        expectEqual(keys.press(1),1);expectNil(keys.press(1))
        expectEqual(keys.press(2),-1);expectNil(keys.press(2))
        keys.release(1);expectEqual(keys.press(1),1)
        expectNil(keys.press(99));keys.reset();expectEqual(keys.press(2),-1)
        expectEqual(ShiftShortcutKeys.brackets.easier,"[")
        expectEqual(ShiftShortcutKeys.brackets.harder,"]")
        expectEqual(ShiftShortcutKeys.jk.easier,"J");expectEqual(ShiftShortcutKeys.jk.harder,"K")
    }
    func testKeyboardForegroundScope() {
        for executable in ["ZwiftAppSilicon","ZwiftApp"] {
            expectTrue(ShiftShortcutScope.allows(executable:executable,isVelox:false,ridePage:false,editing:false))
        }
        for executable in ["ZwiftLauncher-OSX","Safari",""] {
            expectTrue(!ShiftShortcutScope.allows(executable:executable,isVelox:false,ridePage:true,editing:false))
        }
        expectTrue(ShiftShortcutScope.allows(executable:"",isVelox:true,ridePage:true,editing:false))
        expectTrue(!ShiftShortcutScope.allows(executable:"",isVelox:true,ridePage:false,editing:false))
        expectTrue(!ShiftShortcutScope.allows(executable:"",isVelox:true,ridePage:true,editing:true))
    }
    private func buttons(_ mask:UInt32)->Data {
        var d=Data([0x23,8]); var n=mask
        repeat { var b=UInt8(n & 127); n >>= 7; if n>0 { b |= 128 }; d.append(b) } while n>0
        return d
    }
    func testClick2EdgesNoRepeatAndIndependentPucks() {
        var left=ClickDecoder(), right=ClickDecoder()
        expectEqual(right.shifts(buttons(~0x1000),rightOnly:false),[1])
        expectEqual(right.shifts(buttons(~0x1000),rightOnly:false),[])
        expectEqual(left.shifts(buttons(~0x100),rightOnly:false),[-1])
        expectEqual(right.shifts(buttons(.max),rightOnly:false),[])
        expectEqual(right.shifts(buttons(~0x1000),rightOnly:false),[1])
    }
    func testRightOnlyBMapping() {
        var decoder=ClickDecoder()
        expectEqual(decoder.shifts(buttons(~0x20),rightOnly:true),[-1])
        decoder.reset(); expectEqual(decoder.shifts(buttons(~0x100),rightOnly:true),[])
    }
    func testMalformedControllerPackets() {
        var decoder=ClickDecoder()
        for d in [Data(),Data([0x23]),Data([0x23,8,128]),Data([0x23,10,255,255]),Data([0x37,8,0,16,1])] { expectEqual(decoder.shifts(d,rightOnly:false),[]) }
        expectNil(Proto.field(1,in:Data([8]+Array(repeating:255,count:12))))
    }
    func testFragmentedAndCoalescedTCPFrames() throws {
        let first=DirConFrame(id:1,sequence:19), second=DirConFrame(id:3,sequence:20,body:GATT.feature)
        var b=Data(first.encoded.prefix(4)); expectNil(try DirConFrame.extract(from:&b))
        b.append(first.encoded.dropFirst(4)); b.append(second.encoded)
        expectEqual(try DirConFrame.extract(from:&b),first); expectEqual(try DirConFrame.extract(from:&b),second); expectTrue(b.isEmpty)
    }
    func testBadNetworkFrames() {
        var b=Data([2,1,0,0,0,0]); expectThrows(try DirConFrame.extract(from:&b))
        b=Data([1,1,0,0,255,255]); expectThrows(try DirConFrame.extract(from:&b))
    }
    func testUUIDNetworkByteOrderAndFeatures() {
        expectEqual(GATT.service,Data([0,0,0x18,0x26,0,0,0x10,0,0x80,0,0,0x80,0x5F,0x9B,0x34,0xFB]))
        expectEqual(GATT.features.count,8); expectEqual(GATT.range.u16(2),1000)
    }
    func testActualTCPControlLifecycle() {
        let server=NetworkTrainer()
        let ready=Expectation(description:"control listener ready")
        server.state={ if $0 == "Waiting for Zwift" { ready.fulfill() } }
        var commands:[Data]=[]
        var lost=false
        server.onControl={ d,done in commands.append(d); done(1) }
        server.onLost={ lost=true }
        server.start(port:0,advertise:false); wait(for:[ready],timeout:5)
        guard let port=server.boundPort else { fail("No port"); return }
        let c=NWConnection(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!,using:.tcp)
        var frames:[DirConFrame]=[]; var buffer=Data()
        func receive() {
            c.receive(minimumIncompleteLength:1,maximumLength:8192) { d,_,finished,error in
                if let d { buffer.append(d) }
                do { while let f=try DirConFrame.extract(from:&buffer) { frames.append(f) } } catch { fail("Bad server frame") }
                if !finished && error == nil { receive() }
            }
        }
        let linked=Expectation(description:"TCP connected")
        c.stateUpdateHandler={ if case .ready=$0 { receive(); linked.fulfill() } }
        c.start(queue:.main);wait(for:[linked],timeout:5)
        func exchange(_ request:DirConFrame,_ expectedCount:Int) -> [DirConFrame] {
            frames=[]
            c.send(content:request.encoded,completion:.contentProcessed { e in expectNil(e) })
            let end=Date().addingTimeInterval(3)
            while frames.count<expectedCount && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
            expectEqual(frames.count,expectedCount);return frames
        }
        let subscribe=exchange(DirConFrame(id:5,sequence:1,body:GATT.control+Data([1])),1)
        expectEqual(subscribe.first?.body,GATT.control)
        let denied=exchange(DirConFrame(id:4,sequence:2,body:GATT.control+Data([5,200,0])),2)
        expectEqual(denied.last?.body,GATT.control+Data([0x80,5,5]));expectTrue(commands.isEmpty)
        let acquired=exchange(DirConFrame(id:4,sequence:3,body:GATT.control+Data([0])),2)
        expectEqual(acquired.last?.body,GATT.control+Data([0x80,0,1]))
        let power=exchange(DirConFrame(id:4,sequence:4,body:GATT.control+Data([5,250,0])),2)
        expectEqual(power.last?.body,GATT.control+Data([0x80,5,1]));expectEqual(commands,[Data([0]),Data([5,250,0])])
        let features=exchange(DirConFrame(id:3,sequence:5,body:GATT.feature),1)
        expectEqual(features.first?.body,GATT.feature+GATT.features)
        let missing=exchange(DirConFrame(id:3,sequence:6,body:GATT.uuid("FFFF")),1)
        expectEqual(missing.first?.status,4)
        server.state={ _ in };c.cancel()
        let end=Date().addingTimeInterval(3)
        while !lost && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        expectTrue(lost);server.stop()
    }
    func testActualTCPDiscovery() {
        let ready=Expectation(description:"listener ready"), received=Expectation(description:"discovery response")
        let server=NetworkTrainer()
        server.state={ if $0 == "Waiting for Zwift" { ready.fulfill() } }
        server.start(port:0,advertise:false)
        wait(for:[ready],timeout:5)
        guard let port=server.boundPort else { fail("No listener port"); return }
        let c=NWConnection(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!,using:.tcp)
        c.stateUpdateHandler={ s in
            if case .ready=s {
                c.send(content:DirConFrame(id:1,sequence:42).encoded,completion:.contentProcessed { _ in })
                c.receive(minimumIncompleteLength:22,maximumLength:100) { data,_,_,error in
                    expectNil(error); var b=data ?? Data()
                    let f=try? DirConFrame.extract(from:&b)
                    expectEqual(f,DirConFrame(id:1,sequence:42,body:GATT.service)); received.fulfill()
                }
            }
        }
        c.start(queue:.main); wait(for:[received],timeout:5); c.cancel(); server.state={ _ in }; server.stop()
    }
}

let checks=ProtocolTests()
checks.testTelemetryRoundTrip()
checks.testTruncatedOptionalFieldsAreRejected()
checks.testMoreDataPreservesSpeed()
checks.testSignedPower()
checks.testGearsAndRoadLoad()
checks.testEvenGearingAtReferenceCadence()
checks.testGearTuningAndCadenceResponse()
checks.testCalibrationBoundsKeepAll24GearsDistinct()
checks.testLoadSmoothingRateSettlingAndRelease()
try checks.testOneByTwelveAndThirteen()
try checks.testSramTwoByTwelveOrdering()
try checks.testDrivetrainValidationAndParsing()
try checks.testCassetteGeneratorBoundsAndUniqueness()
checks.testExactRatioRoadPowerAndCommandCap()
try checks.testRiderProfilesRemainIndependent()
try checks.testRiderPersistenceAndMigration()
checks.testClick2EdgesNoRepeatAndIndependentPucks()
checks.testRightOnlyBMapping()
checks.testMalformedControllerPackets()
try checks.testFragmentedAndCoalescedTCPFrames()
checks.testBadNetworkFrames()
checks.testUUIDNetworkByteOrderAndFeatures()
checks.testActualTCPDiscovery()
checks.testActualTCPControlLifecycle()
try checks.testRiderDeletionSelection()
try checks.testRiderDeletionGuards()
try checks.testRiderDeletionPersists()
checks.testKeyboardPressEdges()
checks.testKeyboardForegroundScope()
print("29 check groups completed; \(failures) failures")
exit(failures == 0 ? 0 : 1)
