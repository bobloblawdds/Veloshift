import SwiftUI
import VeloxCore

extension Color {
    static let ink=Color(red:0.055,green:0.067,blue:0.075)
    static let panel=Color(red:0.09,green:0.105,blue:0.115)
    static let line=Color.white.opacity(0.08)
    static let lime=Color(red:0.78,green:0.97,blue:0.38)
    static let muted=Color(red:0.57,green:0.61,blue:0.63)
}
struct ActionStyle: ButtonStyle {
    var prominent=false
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:12,weight:.semibold)).padding(.horizontal,12).padding(.vertical,10)
            .foregroundStyle(prominent ? Color.ink : Color.white)
            .background(prominent ? Color.lime : Color.white.opacity(configuration.isPressed ? 0.15:0.07),in:RoundedRectangle(cornerRadius:8))
            .opacity(configuration.isPressed ? 0.75:1)
    }
}
struct Card<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View {
        content.padding(14).background(Color.panel,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.line,lineWidth:1))
    }
}
struct Eyebrow:View {
    var text:String
    var body:some View { Text(text.uppercased()).font(.system(size:9,weight:.semibold)).tracking(1).foregroundStyle(Color.muted) }
}
struct StatusDot:View {
    var active:Bool
    var body:some View { Circle().fill(active ? Color.lime : Color.muted).frame(width:6,height:6).accessibilityHidden(true) }
}
struct RootView:View {
    @ObservedObject var session:Session
    private var pageTitle:String {
        switch session.page { case "Preferences":return "Riders & gearing";case "Setup guide":return "Setup";case "Activity":return "Activity";case "Devices":return "Devices";default:return "Veloshift" }
    }
    var body:some View {
        VStack(spacing:0) {
            header
            Rectangle().fill(Color.line).frame(height:1)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if session.demo { demoBanner }
                    switch session.page {
                    case "Devices": devices
                    case "Preferences": ProfileEditor(session:session)
                    case "Setup guide": guide
                    case "Activity": activity
                    default: ride
                    }
                }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            }.scrollIndicators(.hidden)
            if session.page == "Ride" { bridgeAction }
        }.background(Color.ink).foregroundStyle(.white).preferredColorScheme(.dark)
        .frame(minWidth:300,minHeight:560)
    }
    private var header:some View {
        HStack(spacing:9) {
            if session.page != "Ride" {
                Button { session.page="Ride" } label: { Image(systemName:"chevron.left").frame(width:22,height:28) }
                    .buttonStyle(.plain).help("Back to ride").accessibilityLabel("Back to ride")
            }
            if session.page == "Ride" { ShiftBikeMark().frame(width:40,height:26).accessibilityHidden(true) }
            Text(pageTitle).font(.system(size:15,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength:4)
            headerButton("antenna.radiowaves.left.and.right","Devices",page:"Devices")
            headerButton("person.crop.circle","Riders and gearing",page:"Preferences")
            Menu {
                Button("Setup guide") { session.page="Setup guide" }
                Button("Activity log") { session.page="Activity" }
                Button("Fit to screen edge") { NotificationCenter.default.post(name:.veloxFitWindow,object:nil) }
                Divider()
                if session.demo { Button("End demo") { session.endDemo() } }
                else { Button("Try demo") { session.startDemo() } }
                Button("Export diagnostics") { session.exportDiagnostics() }
                Divider()
                Text("Veloshift 0.6")
            } label: { Image(systemName:"ellipsis").frame(width:24,height:28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More").accessibilityLabel("More")
        }.padding(.horizontal,16).frame(height:40)
    }
    private func headerButton(_ symbol:String,_ label:String,page:String) -> some View {
        Button { session.page=page } label: { Image(systemName:symbol).font(.system(size:14)).frame(width:26,height:28) }
            .buttonStyle(.plain).foregroundStyle(session.page==page ? Color.lime : Color.muted).help(label).accessibilityLabel(label)
    }
    private var demoBanner:some View {
        HStack(spacing:8) {
            Text("DEMO").font(.system(size:9,weight:.bold)).tracking(1)
            Text("Simulated · hardware off").font(.system(size:10)).foregroundStyle(Color.muted)
            Spacer(minLength:0)
            Button("Exit") { session.endDemo() }.buttonStyle(.plain).font(.system(size:11,weight:.medium))
        }.foregroundStyle(Color.lime).padding(10).background(Color.lime.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
    }
    private var ride:some View {
        VStack(spacing:12) {
            HStack(spacing:8) {
                Eyebrow(text:"Rider")
                Picker("Rider",selection:Binding(get:{ session.profile.id },set:{ session.selectRider($0) })) {
                    ForEach(session.profiles) { Text($0.name).tag($0.id) }
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth:.infinity).disabled(!session.canEditRider)
                    .help(session.canEditRider ? "Choose rider" : "Stop the bridge to switch riders")
            }
            HStack(spacing:10) {
                metric("Power",value:session.metrics.power,unit:"W",tint:.lime)
                metric("Cadence",value:session.metrics.cadence,unit:"rpm",tint:.white)
            }
            gearControls
            HStack(spacing:8) {
                Text(session.mode.rawValue)
                Spacer()
                if session.mode == .erg { Text("Target \(Int(session.commandedPower.rounded())) W").foregroundStyle(.white) }
                else { Text(String(format:"%+.1f%% grade",session.grade)).foregroundStyle(.white) }
            }.font(.system(size:11)).foregroundStyle(Color.muted).padding(.horizontal,2)
            Card {
                VStack(alignment:.leading,spacing:10) {
                    HStack { Eyebrow(text:"Power");Spacer();Text("80 sec").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted) }
                    PowerTrace(values:session.history).frame(height:44).accessibilityLabel("Power history")
                }
            }
            Card {
                VStack(spacing:11) {
                    statusRow("KICKR v5",session.demo ? "Demo" : session.trainerReady ? "Connected" : "Not connected",active:session.demo || session.trainerReady)
                    statusRow("Click 2",session.demo ? "Demo" : session.controllers.isEmpty ? "Not connected" : "\(session.controllers.count) connected",active:session.demo || !session.controllers.isEmpty)
                    statusRow("Zwift",session.demo ? "Demo" : session.network,active:session.network == "Zwift has control" || session.network == "Client connected")
                }
            }
        }
    }
    private var gearControls:some View {
        Card {
            VStack(spacing:10) {
                HStack { Eyebrow(text:session.mode == .erg ? "ERG · shifting paused" : "Gear");Spacer();Text("\(session.gearCount) speeds").font(.system(size:10)).foregroundStyle(Color.muted) }
                HStack(alignment:.firstTextBaseline,spacing:4) {
                    Spacer()
                    Text("\(session.gear)").font(.system(size:68,weight:.light,design:.rounded)).monospacedDigit().contentTransition(.numericText())
                    Text("/ \(session.gearCount)").font(.system(size:18,weight:.light,design:.rounded)).foregroundStyle(Color.muted)
                    Spacer()
                }.foregroundStyle(session.mode == .erg ? Color.muted : Color.white)
                Text(session.drivetrainDescription).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(Color.lime).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing:2) {
                    ForEach(1...max(1,session.gearCount),id:\.self) { index in
                        Capsule().fill(index <= session.gear ? Color.lime.opacity(index==session.gear ? 1:0.45) : Color.white.opacity(0.08)).frame(height:3)
                    }
                }.accessibilityHidden(true).padding(.vertical,2)
                HStack(spacing:10) {
                    Button { session.shift(-1) } label: { Label("Easier",systemImage:"minus").frame(maxWidth:.infinity) }
                        .buttonStyle(ActionStyle()).disabled(session.gear<=1)
                    Button { session.shift(1) } label: { Label("Harder",systemImage:"plus").frame(maxWidth:.infinity) }
                        .buttonStyle(ActionStyle()).disabled(session.gear>=session.gearCount)
                }.disabled(session.mode == .erg || (!session.demo && !session.trainerReady))
                if session.keyboardShiftingEnabled {
                    Text(session.shiftHotkeysRegistered ? "\(session.shiftShortcutKeys.easier) easier · \(session.shiftShortcutKeys.harder) harder" : session.shiftHotkeyConflict ? "Shortcut conflict · see rider settings" : "Shift keys: \(session.shiftShortcutKeys.easier) / \(session.shiftShortcutKeys.harder)")
                        .font(.system(size:9,design:.monospaced)).foregroundStyle(session.shiftHotkeyConflict ? Color.orange : Color.muted).fixedSize(horizontal:false,vertical:true)
                }
            }
        }
    }
    private func metric(_ title:String,value:Double,unit:String,tint:Color) -> some View {
        Card {
            VStack(alignment:.leading,spacing:8) {
                Eyebrow(text:title)
                HStack(alignment:.firstTextBaseline,spacing:4) {
                    Text(String(format:"%.0f",value)).font(.system(size:39,weight:.light,design:.rounded)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.65)
                    Text(unit).font(.system(size:10)).foregroundStyle(Color.muted)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.frame(maxWidth:.infinity)
    }
    private func statusRow(_ label:String,_ detail:String,active:Bool) -> some View {
        HStack(spacing:8) {
            StatusDot(active:active)
            Text(label).font(.system(size:11,weight:.medium)).fixedSize()
            Spacer(minLength:6)
            Text(detail).font(.system(size:10)).foregroundStyle(Color.muted).multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var bridgeAction:some View {
        VStack(spacing:0) {
            Rectangle().fill(Color.line).frame(height:1)
            Group {
                if session.demo {
                    Button { session.endDemo() } label: { Text("End demo").frame(maxWidth:.infinity) }.buttonStyle(ActionStyle())
                } else if session.bridgeActive {
                    Button { session.stopBridge() } label: { Label("Stop bridge",systemImage:"stop.fill").frame(maxWidth:.infinity) }.buttonStyle(ActionStyle())
                } else {
                    Button {
                        if session.trainerReady { session.startBridge() } else { session.scan() }
                    } label: {
                        Label(session.trainerReady ? "Start bridge" : "Connect devices",systemImage:session.trainerReady ? "play.fill" : "antenna.radiowaves.left.and.right").frame(maxWidth:.infinity)
                    }.buttonStyle(ActionStyle(prominent:true))
                }
            }.padding(12)
        }
    }
    private var devices:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(session.bluetooth).font(.system(size:11)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true)
            Button("Scan devices",systemImage:"arrow.clockwise") { session.scan() }.buttonStyle(ActionStyle(prominent:true))
            if session.devices.isEmpty {
                Card { Text("Pedal to wake the KICKR. Press a button on each Click, then scan.").font(.system(size:12)).foregroundStyle(Color.muted).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true) }
            }
            ForEach(session.devices) { device in
                Card {
                    VStack(alignment:.leading,spacing:10) {
                        Text(device.name).font(.system(size:13,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                        Text("\(device.role) · \(device.rssi) dBm").font(.system(size:10)).foregroundStyle(Color.muted)
                        if let input=session.inputs[device.id] { Text("Input: \(input.formatted(date:.omitted,time:.standard))").font(.system(size:10)).foregroundStyle(Color.lime) }
                        let connected=device.role == "KICKR v5" ? session.trainerReady : session.controllers[device.id] != nil
                        Button(connected ? "Connected" : "Connect") { session.connect(device) }.buttonStyle(ActionStyle(prominent:!connected)).disabled(connected)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            Card {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Right Click only",isOn:$session.rightOnly).toggleStyle(.switch).font(.system(size:12)).tint(.lime)
                    Text("Right-only: + harder, B easier. Both controllers: − left, + right.").font(.system(size:11)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true)
                    DisclosureGroup("Left Click not responding?") {
                        Text("Pair it directly to official Zwift for at least 2 minutes, then disconnect it there and reconnect here. Some firmware requires this daily. Alternatively use Right Click only.").font(.system(size:11)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true).padding(.top,6)
                    }.font(.system(size:11))
                }
            }
            Button("Disconnect all") { session.stopAll() }.buttonStyle(ActionStyle())
        }
    }
    private var guide:some View {
        VStack(alignment:.leading,spacing:12) {
            helpCard("1. Connect hardware","Update KICKR v5 firmware in Wahoo, then close Wahoo. Disconnect the physical trainer and Clicks in Zwift. Open Devices in Veloshift, scan, and connect.")
            helpCard("2. Choose rider","Open Riders & gearing. Enter the rider’s weight and drivetrain, then save. Stop the bridge before switching riders or applying changes. Set the correct rider in Zwift separately.")
            helpCard("3. Pair Zwift","Start the bridge. In Zwift choose Veloshift KICKR v5 with the network icon for Power Source, Resistance, and Cadence. Allow Bluetooth and Local Network permissions when asked.")
            helpCard("Shifting","Use the Click buttons, onscreen Easier/Harder, or [ for easier and ] for harder. Single-key shortcuts work with Zwift or Veloshift’s Ride view focused. Choose J/K instead in rider settings if needed. ERG workouts pause shifting. The 1,000 W command limit still applies.")
            Button("Connect devices") { session.scan() }.buttonStyle(ActionStyle(prominent:true))
        }
    }
    private func helpCard(_ title:String,_ detail:String) -> some View {
        Card {
            VStack(alignment:.leading,spacing:8) { Text(title).font(.system(size:13,weight:.semibold));Text(detail).font(.system(size:11)).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true).lineSpacing(3) }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private var activity:some View {
        VStack(alignment:.leading,spacing:12) {
            Button("Export log") { session.exportDiagnostics() }.buttonStyle(ActionStyle())
            ForEach(session.events.prefix(100)) { event in
                VStack(alignment:.leading,spacing:4) {
                    Text(event.date.formatted(date:.omitted,time:.standard)).font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted)
                    Text(event.text).font(.system(size:11)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,6)
                Divider().overlay(Color.line)
            }
        }
    }
}
struct PowerTrace:View {
    let values:[Double]
    var body:some View {
        Canvas { ctx,size in
            for n in 0..<3 { let y=Double(n)*size.height/2;var p=Path();p.move(to:CGPoint(x:0,y:y));p.addLine(to:CGPoint(x:size.width,y:y));ctx.stroke(p,with:.color(.white.opacity(0.05)),style:StrokeStyle(lineWidth:1,dash:[3,4])) }
            guard values.count>1 else { return }
            let ceiling=max(300,values.max() ?? 300)*1.15
            var line=Path()
            for (i,v) in values.enumerated() { let p=CGPoint(x:Double(i)/Double(values.count-1)*size.width,y:size.height-max(0,v)/ceiling*size.height);if i==0 { line.move(to:p) } else { line.addLine(to:p) } }
            var fill=line;fill.addLine(to:CGPoint(x:size.width,y:size.height));fill.addLine(to:CGPoint(x:0,y:size.height));fill.closeSubpath()
            ctx.fill(fill,with:.linearGradient(Gradient(colors:[.lime.opacity(0.2),.lime.opacity(0)]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height)))
            ctx.stroke(line,with:.color(.lime),style:StrokeStyle(lineWidth:1.7,lineCap:.round,lineJoin:.round))
        }
    }
}
