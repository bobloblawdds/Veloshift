import Foundation
import Network

/// FTMS GATT transported over Wahoo Direct Connect. The hardware remains BLE.
public final class NetworkTrainer {
    final class Peer {
        let connection: NWConnection
        var buffer = Data()
        var subscriptions = Set<Data>()
        init(_ c: NWConnection) { connection = c }
    }
    public var log: (String) -> Void = { _ in }
    public var state: (String) -> Void = { _ in }
    public var onControl: (Data, @escaping (UInt8) -> Void) -> Void = { _, done in done(4) }
    public var onLost: () -> Void = {}
    public var metrics = BikeMetrics()
    private var listener: NWListener?
    private var peer: Peer?
    private var generation = UUID()
    private var ownsControl = false
    public var connected: Bool { peer != nil }
    public init() {}
    public var boundPort: UInt16? { listener?.port?.rawValue }
    public func start(port: UInt16 = 36866, advertise: Bool = true) {
        stop()
        let token = generation
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let l = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue:port) ?? .any)
            let txt = NWTXTRecord(["ble-service-uuids":"0x1826", "mac-address":"C2:56:45:4C:4F:58", "serial-number":"VELOX-K5-0001"])
            if advertise { l.service = NWListener.Service(name:"Veloshift KICKR v5", type:"_wahoo-fitness-tnp._tcp", txtRecord:txt) }
            l.stateUpdateHandler = { [weak self] s in
                guard let self, self.generation == token else { return }
                switch s {
                case .ready: self.state("Waiting for Zwift"); self.log("Network trainer listening on port 36866")
                case .failed(let e): self.state("Network unavailable"); self.log("Network error: \(e.localizedDescription)"); self.stop()
                case .waiting(let e): self.log("Network waiting: \(e.localizedDescription)")
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] c in
                guard let self, self.generation == token else { c.cancel(); return }
                guard self.peer == nil else { c.cancel(); return }
                let p = Peer(c); self.peer=p
                c.stateUpdateHandler = { [weak self, weak p] s in
                    guard let self, let p, self.peer === p else { return }
                    switch s {
                    case .ready: self.state("Client connected"); self.log("Training app connected to Veloshift"); self.receive(p)
                    case .failed, .cancelled: self.drop(p)
                    default: break
                    }
                }
                c.start(queue:.main)
            }
            listener=l; l.start(queue:.main)
        } catch { state("Network unavailable"); log(error.localizedDescription) }
    }
    public func stop() {
        generation = UUID(); listener?.cancel(); listener=nil
        if let p=peer { drop(p) }
    }
    private func drop(_ p: Peer) {
        guard peer === p else { return }
        peer=nil; ownsControl=false; p.connection.cancel(); state("Waiting for Zwift"); log("Training app disconnected; releasing load"); onLost()
    }
    private func receive(_ p: Peer) {
        p.connection.receive(minimumIncompleteLength:1,maximumLength:8192) { [weak self, weak p] data, _, finished, error in
            guard let self, let p, self.peer === p else { return }
            if let data { p.buffer.append(data) }
            do {
                while let frame = try DirConFrame.extract(from:&p.buffer) { self.handle(frame,p) }
            } catch { self.log("Rejected malformed network frame"); self.drop(p); return }
            if finished || error != nil { self.drop(p) } else { self.receive(p) }
        }
    }
    private func send(_ f: DirConFrame, _ p: Peer) {
        guard peer === p else { return }
        p.connection.send(content:f.encoded, completion:.contentProcessed { [weak self, weak p] e in
            if e != nil, let p { self?.drop(p) }
        })
    }
    private func handle(_ f: DirConFrame, _ p: Peer) {
        func reply(_ body: Data = Data(), _ status: UInt8 = 0) { send(DirConFrame(id:f.id,sequence:f.sequence,status:status,body:body),p) }
        if f.id == 1 { guard f.body.isEmpty else { reply(Data(),2); return }; reply(GATT.service); return }
        guard f.body.count >= 16 else { reply(Data(),2); return }
        let uuid = Data(f.body.prefix(16)); let value = Data(f.body.dropFirst(16))
        if f.id == 2 {
            guard f.body.count == 16, uuid == GATT.service else { reply(Data(),3); return }
            var d = uuid; for (id,flags) in GATT.chars { d.append(id); d.append(flags) }; reply(d); return
        }
        guard let ch = GATT.chars.first(where: { $0.0 == uuid }) else { reply(Data(),4); return }
        switch f.id {
        case 3:
            guard f.body.count == 16, ch.1 & 1 != 0 else { reply(Data(),5); return }
            reply(uuid + (uuid == GATT.feature ? GATT.features : GATT.range))
        case 5:
            guard value.count == 1, value[0] <= 1, ch.1 & 4 != 0 else { reply(Data(),5); return }
            if value[0] == 1 { p.subscriptions.insert(uuid) } else { p.subscriptions.remove(uuid) }; reply(uuid)
        case 4:
            guard uuid == GATT.control, let op = value.first else { reply(Data(),5); return }
            // A successful GATT write is distinct from the FTMS procedure result.
            guard p.subscriptions.contains(GATT.control) else { reply(Data(),6); return }
            reply(uuid)
            if op != 0 && !ownsControl { notify(GATT.control,Data([0x80,op,5])); return }
            onControl(value) { [weak self, weak p] code in
                guard let self, let p, self.peer === p else { return }
                if op == 0 && code == 1 { self.ownsControl=true; self.state("Zwift has control") }
                self.notify(GATT.control,Data([0x80,op,code]))
            }
        default: reply(Data(),1)
        }
    }
    public func notify(_ uuid: Data, _ value: Data) {
        guard let p=peer, p.subscriptions.contains(uuid) else { return }
        send(DirConFrame(id:6,body:uuid+value),p)
    }
    public func publish(_ m: BikeMetrics) { metrics=m; notify(GATT.bike,m.packet) }
}
