import Foundation
import CoreBluetooth
import VeloxCore

struct NearbyDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var role: String
}
final class Hardware: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var log: (String) -> Void = { _ in }
    var onDevices: ([NearbyDevice]) -> Void = { _ in }
    var onBluetooth: (String) -> Void = { _ in }
    var onTrainer: (Bool) -> Void = { _ in }
    var onController: (UUID,String,Bool) -> Void = { _,_,_ in }
    var onMetrics: (BikeMetrics) -> Void = { _ in }
    var onShift: (Int) -> Void = { _ in }
    var onInput: (UUID) -> Void = { _ in }
    var rightOnly = false
    private var manager: CBCentralManager?
    private var devices: [UUID:CBPeripheral] = [:]
    private var nearby: [UUID:NearbyDevice] = [:]
    private var roles: [UUID:String] = [:]
    private var connected = Set<UUID>()
    private var trainer: CBPeripheral?
    private var control: CBCharacteristic?
    private var decoders: [UUID:ClickDecoder] = [:]
    private var rx: [UUID:CBCharacteristic] = [:]
    private var subscribed: [UUID:Set<CBUUID>] = [:]
    private var pendingHandshake = Set<UUID>()
    private var queue: [(Data,(Bool)->Void)] = []
    private var pending: (Data,(Bool)->Void)?
    private var timeout: DispatchWorkItem?
    private var scanTimeout: DispatchWorkItem?
    private var lastMetrics = BikeMetrics()
    private var ready = false
    private let ftms = CBUUID(string:"1826"), bike = CBUUID(string:"2AD2"), cp = CBUUID(string:"2AD9")
    private let asyncID = CBUUID(string:"00000002-19CA-4651-86E5-FA29DCDD09D1")
    private let rxID = CBUUID(string:"00000003-19CA-4651-86E5-FA29DCDD09D1")
    private let txID = CBUUID(string:"00000004-19CA-4651-86E5-FA29DCDD09D1")
    func scan() {
        if manager == nil { manager = CBCentralManager(delegate:self,queue:.main) }
        else if manager?.state == .poweredOn { beginScan() }
        else { reportState() }
    }
    private func beginScan() {
        nearby.removeAll(); onDevices([])
        manager?.scanForPeripherals(withServices:nil, options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
        log("Scanning for KICKR and Click 2. Pedal and press a controller button.")
        scanTimeout?.cancel()
        let t = DispatchWorkItem { [weak self] in self?.manager?.stopScan(); self?.log("Scan finished. Scan again if your device is missing.") }
        scanTimeout=t; DispatchQueue.main.asyncAfter(deadline:.now()+20,execute:t)
    }
    private func reportState() {
        guard let manager else { return }
        let s: String
        switch manager.state {
        case .poweredOn: s="Bluetooth ready"
        case .poweredOff: s="Turn Bluetooth on in System Settings"
        case .unauthorized: s="Allow Veloshift in System Settings → Privacy & Security → Bluetooth"
        case .unsupported: s="Bluetooth LE unavailable"
        default: s="Bluetooth starting"
        }
        onBluetooth(s)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        reportState(); if central.state == .poweredOn { beginScan() }
        else { failTrainer(); for id in connected { onController(id,roles[id] ?? "Click",false) }; connected.removeAll() }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String:Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unknown"
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let kind: String
        if let m=manufacturer, m.count >= 3, m.u16(0) == 2378 {
            switch m[2] { case 10: kind="Right Click 2"; case 11: kind="Left Click 2"; default: return }
        } else if name.uppercased().contains("KICKR") { kind="KICKR v5" }
        else { return }
        devices[peripheral.identifier]=peripheral; nearby[peripheral.identifier]=NearbyDevice(id:peripheral.identifier,name:name,rssi:RSSI.intValue,role:kind)
        onDevices(nearby.values.sorted { $0.role < $1.role })
    }
    func connect(_ id: UUID) {
        guard let p=devices[id], let found=nearby[id] else { return }
        if connected.contains(id) { return }
        if found.role == "KICKR v5", let old=trainer, old.identifier != id { manager?.cancelPeripheralConnection(old) }
        roles[id]=found.role; p.delegate=self; log("Connecting to \(found.name)…"); manager?.connect(p)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected.insert(peripheral.identifier)
        if roles[peripheral.identifier] == "KICKR v5" { trainer=peripheral }
        else { decoders[peripheral.identifier]=ClickDecoder() }
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Connection failed: \(error?.localizedDescription ?? "device unavailable")")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected.remove(peripheral.identifier)
        if peripheral.identifier == trainer?.identifier { failTrainer() }
        else { onController(peripheral.identifier,roles[peripheral.identifier] ?? "Click",false) }
        rx[peripheral.identifier]=nil; subscribed[peripheral.identifier]=nil; decoders[peripheral.identifier]=nil; pendingHandshake.remove(peripheral.identifier)
        log("\(peripheral.name ?? "Device") disconnected. Wake it and scan to reconnect.")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { log("Service discovery failed: \(error!.localizedDescription)"); return }
        let services=peripheral.services ?? []
        if peripheral === trainer && !services.contains(where: { $0.uuid == ftms }) {
            log("No FTMS service. Confirm KICKR v5 and update firmware in Wahoo."); manager?.cancelPeripheralConnection(peripheral); return
        }
        for service in services { peripheral.discoverCharacteristics(nil,for:service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { log("Characteristic discovery failed"); return }
        let id = peripheral.identifier
        for c in service.characteristics ?? [] {
            if peripheral === trainer {
                if c.uuid == cp { control=c; peripheral.setNotifyValue(true,for:c) }
                if c.uuid == bike { peripheral.setNotifyValue(true,for:c) }
            } else {
                if c.uuid == rxID { rx[id]=c }
                if c.uuid == asyncID || c.uuid == txID { peripheral.setNotifyValue(true,for:c) }
                if c.uuid == CBUUID(string:"2A26"), c.properties.contains(.read) { peripheral.readValue(for:c) }
            }
        }
        handshake(peripheral)
    }
    private func handshake(_ p: CBPeripheral) {
        let id=p.identifier
        guard !pendingHandshake.contains(id), let c=rx[id], let set=subscribed[id], set.contains(asyncID), set.contains(txID) else { return }
        pendingHandshake.insert(id)
        p.writeValue(Data("RideOn".utf8),for:c,type:c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        if roles[id] == "Left Click 2" {
            p.writeValue(Data([0xFF,0x04,0x00]),for:c,type:c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        }
        onController(id,roles[id] ?? "Click 2",true)
        log("\(roles[id] ?? "Click 2") subscribed; press + or − to verify input")
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else { log("Could not subscribe: \(error?.localizedDescription ?? "notifications off")"); return }
        if peripheral === trainer && characteristic.uuid == cp {
            command(Data([0])) { [weak self] ok in
                guard let self else { return }; self.ready=ok; self.onTrainer(ok)
                self.log(ok ? "KICKR control granted" : "KICKR denied control. Close other training apps.")
            }
        } else {
            subscribed[peripheral.identifier,default:[]].insert(characteristic.uuid); handshake(peripheral)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let d=characteristic.value else { return }
        if peripheral === trainer {
            if characteristic.uuid == bike, let m=BikeMetrics.decode(d,previous:lastMetrics) { lastMetrics=m; onMetrics(m) }
            if characteristic.uuid == cp, d.count >= 3, d[0] == 0x80, let pending, d[1] == pending.0.first {
                self.pending=nil; timeout?.cancel(); pending.1(d[2] == 1); pump()
            }
        } else if characteristic.uuid == asyncID || characteristic.uuid == txID {
            let id=peripheral.identifier
            if d.first == 0x23 {
                onInput(id)
                if var decoder=decoders[id] { let shifts=decoder.shifts(d,rightOnly:rightOnly); decoders[id]=decoder; for s in shifts { onShift(s) } }
            } else if d.starts(with:Data([0xFF,0x05])) { log("Click 2 stopped sending input. Unlock in Zwift, or select Right Click only.") }
        } else if characteristic.uuid == CBUUID(string:"2A26") { log("Click firmware: \(String(data:d,encoding:.utf8) ?? d.map { String(format:"%02x",$0) }.joined())") }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log("Bluetooth write failed: \(error.localizedDescription)"); if peripheral === trainer { failTrainer() } }
    }
    func command(_ data: Data, completion: @escaping (Bool)->Void = { _ in }) {
        guard trainer?.state == .connected, control != nil else { completion(false); return }
        queue.append((data,completion)); pump()
    }
    private func pump() {
        guard pending == nil, !queue.isEmpty, let trainer, let control else { return }
        pending=queue.removeFirst(); let packet=pending!.0
        trainer.writeValue(packet,for:control,type:.withResponse)
        let t=DispatchWorkItem { [weak self] in
            guard let self else { return }; self.log("KICKR control response timed out. Reconnect before riding.")
            let p=self.trainer; self.failTrainer(); if let p { self.manager?.cancelPeripheralConnection(p) }
        }
        timeout=t; DispatchQueue.main.asyncAfter(deadline:.now()+4,execute:t)
    }
    private func failTrainer() {
        timeout?.cancel(); let callbacks = queue.map { $0.1 } + (pending.map { [$0.1] } ?? [])
        queue.removeAll(); pending=nil; ready=false; control=nil; trainer=nil; lastMetrics=BikeMetrics(); onTrainer(false)
        for cb in callbacks { cb(false) }
    }
    func disconnectAll() {
        manager?.stopScan(); scanTimeout?.cancel()
        for id in connected { if let p=devices[id] { manager?.cancelPeripheralConnection(p) } }
        failTrainer()
    }
}
