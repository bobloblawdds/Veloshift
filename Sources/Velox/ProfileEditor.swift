import SwiftUI
import VeloxCore

struct ProfileEditor: View {
    @ObservedObject var session: Session
    @State private var draft=RiderProfile()
    @State private var rings="48, 35"
    @State private var cogs=Drivetrain.sram1036.map(String.init).joined(separator:", ")
    @State private var rearSpeeds=12
    @State private var wheelMM=2105.0
    @State private var smallest=10
    @State private var largest=36
    @State private var notice=""
    @State private var showAllGears=false
    @State private var riderToDelete:RiderProfile?
    @State private var confirmingDeletion=false
    private var candidate: RiderProfile? { try? makeProfile() }
    private var validation: String? {
        do { _=try makeProfile();return nil } catch { return error.localizedDescription }
    }
    private func makeProfile() throws -> RiderProfile {
        var p=draft
        if p.style == .drivetrain {
            let rear=try Drivetrain.parseTeeth(cogs)
            guard rear.count == rearSpeeds else { throw SetupError.invalid("Rear speeds is \(rearSpeeds), but the list has \(rear.count) sprockets.") }
            p.drivetrain=try Drivetrain(chainrings:Drivetrain.parseTeeth(rings),cassette:rear,circumference:wheelMM/1000).validated()
        }
        return try p.validated()
    }
    private func loadProfile() {
        draft=session.profile;rings=draft.drivetrain.chainrings.map(String.init).joined(separator:", ")
        cogs=draft.drivetrain.cassette.map(String.init).joined(separator:", ")
        rearSpeeds=draft.drivetrain.cassette.count;wheelMM=draft.drivetrain.circumference*1000
        smallest=draft.drivetrain.cassette.min() ?? 10;largest=draft.drivetrain.cassette.max() ?? 36;notice="";showAllGears=false
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                Picker("Rider",selection:Binding(get:{ session.profile.id },set:{ session.selectRider($0) })) {
                    ForEach(session.profiles) { p in Text(p.name).tag(p.id) }
                }.labelsHidden().frame(maxWidth:.infinity)
                Button { session.addRider() } label: { Image(systemName:"person.badge.plus").frame(width:30,height:28) }
                    .buttonStyle(.plain).help("Add rider").accessibilityLabel("Add rider").disabled(session.profiles.count>=12)
                Button(role:.destructive) { riderToDelete=session.profile;confirmingDeletion=true } label: { Image(systemName:"trash").frame(width:28,height:28) }
                    .buttonStyle(.plain).foregroundStyle(Color.muted).help(session.profiles.count>1 ? "Delete selected rider" : "Keep at least one rider").accessibilityLabel("Delete selected rider").disabled(session.profiles.count<=1)
            }.disabled(!session.canEditRider)
            if !session.canEditRider { note("Stop the bridge before changing riders or gearing.",tint:.lime) }
            VStack(alignment:.leading,spacing:12) {
                identity
                if draft.style == .evenEffort { comfort } else { drivetrain }
                if let validation { note(validation,tint:.orange) }
                VStack(spacing:8) {
                    Button("Save rider & gearing") {
                        do { try session.saveRider(makeProfile());notice="Saved \(session.profile.name)." }
                        catch { notice=error.localizedDescription }
                    }.buttonStyle(ActionStyle(prominent:true)).disabled(candidate == nil)
                    Button("Discard edits") { loadProfile() }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Color.muted)
                }.frame(maxWidth:.infinity)
                if !notice.isEmpty { note(notice,tint:.lime) }
                if let candidate { preview(candidate) }
            }.disabled(!session.canEditRider)
            Card {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Right Click only",isOn:$session.rightOnly).toggleStyle(.switch).tint(.lime)
                    note("+ harder, B easier. Otherwise use − left / + right.")
                }
            }
            Card {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Keyboard shifting",isOn:$session.keyboardShiftingEnabled).toggleStyle(.switch).tint(.lime)
                    if session.keyboardShiftingEnabled {
                        Picker("Keys",selection:$session.shiftShortcutKeys) { ForEach(ShiftShortcutKeys.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu)
                        note("\(session.shiftShortcutKeys.easier) easier · \(session.shiftShortcutKeys.harder) harder — no modifiers")
                        note(session.shiftHotkeyStatus,tint:session.shiftHotkeyConflict ? .orange : .muted)
                    }
                }
            }
        }.alert("Delete rider?",isPresented:$confirmingDeletion,presenting:riderToDelete) { rider in
            Button("Cancel",role:.cancel) { riderToDelete=nil }
            Button("Delete",role:.destructive) {
                do { try session.deleteRider(rider.id);loadProfile() }
                catch { notice=error.localizedDescription }
                riderToDelete=nil
            }
        } message: { rider in
            Text("Delete “\(rider.name)” and their saved gearing from this Mac? This cannot be undone.")
        }.font(.system(size:12)).onAppear { loadProfile() }.onChange(of:session.profile.id) { _,_ in loadProfile() }
    }
    private func note(_ text:String,tint:Color = .muted) -> some View {
        Text(text).font(.system(size:11)).foregroundStyle(tint).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
    }
    private var identity:some View {
        Card {
            VStack(alignment:.leading,spacing:12) {
                Eyebrow(text:"Rider")
                TextField("Name",text:$draft.name).textFieldStyle(.roundedBorder).accessibilityLabel("Rider name")
                HStack { Text("Weight");Spacer();TextField("kg",value:$draft.weight,format:.number).textFieldStyle(.roundedBorder).frame(width:70).accessibilityLabel("Rider weight");Text("kg").foregroundStyle(Color.muted) }
                Picker("Gearing",selection:$draft.style) { ForEach(GearingStyle.allCases,id:\.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                note(draft.style == .evenEffort ? "24 evenly spaced effort levels." : "Actual tooth ratios, ordered easiest to hardest.")
            }
        }
    }
    private var comfort:some View {
        Card {
            VStack(alignment:.leading,spacing:12) {
                Eyebrow(text:"Even effort")
                HStack { Text("Gear 12");Spacer();Text("\(Int(draft.cruiseWatts)) W").foregroundStyle(Color.lime) }
                Slider(value:$draft.cruiseWatts,in:75...400,step:5).tint(.lime).accessibilityLabel("Gear 12 cruising effort")
                HStack { Text("Step");Spacer();Text(String(format:"%.1f W",draft.cruiseWatts*draft.stepFraction)).foregroundStyle(Color.lime) }
                Slider(value:$draft.stepFraction,in:0.03...0.08,step:0.005).tint(.lime).accessibilityLabel("Shift spacing")
                note("Reference: 90 rpm, flat road, no wind.")
            }
        }
    }
    private var drivetrain:some View {
        VStack(alignment:.leading,spacing:12) {
            Card {
                VStack(alignment:.leading,spacing:12) {
                    Eyebrow(text:"Drivetrain")
                    Button("SRAM 48/35 · 10–36") {
                        rings="48, 35";cogs=Drivetrain.sram1036.map(String.init).joined(separator:", ");rearSpeeds=12;smallest=10;largest=36
                        notice="Preset loaded. Save to apply."
                    }.buttonStyle(ActionStyle())
                    VStack(alignment:.leading,spacing:6) {
                        Text("Chainring teeth")
                        TextField("48 or 48, 35",text:$rings).textFieldStyle(.roundedBorder).accessibilityLabel("Chainring teeth")
                    }
                    HStack { Text("Rear speeds");Spacer();Stepper("\(rearSpeeds)",value:$rearSpeeds,in:1...24).fixedSize().accessibilityLabel("Rear speeds") }
                    VStack(alignment:.leading,spacing:6) {
                        Text("Cassette teeth")
                        TextField("10, 11, 12…",text:$cogs,axis:.vertical).lineLimit(2...4).textFieldStyle(.roundedBorder).accessibilityLabel("Cassette tooth counts")
                        note("Enter every sprocket. 2×12 gives 24 combinations, including overlaps.")
                    }
                    HStack { Text("Wheel circumference").fixedSize(horizontal:false,vertical:true);Spacer();TextField("mm",value:$wheelMM,format:.number).textFieldStyle(.roundedBorder).frame(width:72).accessibilityLabel("Wheel circumference");Text("mm").foregroundStyle(Color.muted) }
                    DisclosureGroup("Generate from a range") {
                        VStack(alignment:.leading,spacing:10) {
                            HStack {
                                TextField("Smallest",value:$smallest,format:.number).textFieldStyle(.roundedBorder).accessibilityLabel("Smallest sprocket")
                                Text("–").foregroundStyle(Color.muted)
                                TextField("Largest",value:$largest,format:.number).textFieldStyle(.roundedBorder).accessibilityLabel("Largest sprocket")
                            }
                            Button("Generate teeth") {
                                do { cogs=try Drivetrain.approximateCassette(speeds:rearSpeeds,smallest:smallest,largest:largest).map(String.init).joined(separator:", ");notice="Approximate list generated. Save to apply." }
                                catch { notice=error.localizedDescription }
                            }.buttonStyle(ActionStyle())
                            note("Approximation only. Use the manufacturer’s tooth list for an exact match.")
                        }.padding(.top,8)
                    }.font(.system(size:11))
                }
            }
            Card {
                VStack(alignment:.leading,spacing:10) {
                    HStack { Text("Road load");Spacer();Text("\(Int((draft.loadScale*100).rounded()))%").foregroundStyle(Color.lime) }
                    Slider(value:$draft.loadScale,in:0.25...1,step:0.05).tint(.lime).accessibilityLabel("Road load scale")
                    note("100% uses the full modeled load. Lower values assist effort. Ratios and measured power stay the same; ERG is unaffected.")
                }
            }
        }
    }
    private func preview(_ p:RiderProfile) -> some View {
        let table=p.style == .drivetrain ? p.drivetrain.gears : []
        let indices=table.isEmpty ? [1,12,24] : showAllGears ? table.map(\.id) : Array(Set([1,p.startingGear,p.gearCount])).sorted()
        let highest=p.roadModel(gear:p.gearCount)
        return Card {
            VStack(alignment:.leading,spacing:10) {
                HStack { Eyebrow(text:"Preview");Spacer();Text("\(p.gearCount) gears").foregroundStyle(Color.lime) }
                note("90 rpm · flat · no wind · 9 kg bike")
                ForEach(indices,id:\.self) { index in
                    let model=p.roadModel(gear:index)
                    HStack(spacing:8) {
                        Text("\(index)").foregroundStyle(Color.muted).frame(width:22,alignment:.leading)
                        Text(table.first(where:{ $0.id == index })?.label ?? "Even effort").frame(maxWidth:.infinity,alignment:.leading)
                        Text(model.requiredPower(cadence:90)>1000 ? "\(Int(model.requiredPower(cadence:90).rounded())) → 1000 W" : "\(Int(model.target(cadence:90).rounded())) W").lineLimit(1).minimumScaleFactor(0.8)
                    }.font(.system(size:11,design:.monospaced))
                }
                if !table.isEmpty {
                    Button(showAllGears ? "Show summary" : "Show all \(p.gearCount) gears") { showAllGears.toggle() }.buttonStyle(.plain).foregroundStyle(Color.lime).font(.system(size:11))
                }
                if highest.requiredPower(cadence:90)>1000 { note("Upper gears exceed the 1,000 W cap here and may feel identical.",tint:.orange) }
                note("Modeled watts; actual load varies with cadence, hills and wind. Set your rider in Zwift separately.")
            }
        }
    }
}
