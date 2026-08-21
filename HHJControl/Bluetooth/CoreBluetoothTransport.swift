@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class CoreBluetoothTransport: NSObject, BluetoothTransport {
    private struct PendingWrite {
        let data: Data
        let characteristicUUID: String
        let identifier: UUID
    }

    var eventHandler: ((BluetoothTransportEvent) -> Void)?

    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var characteristics: [UUID: [String: CBCharacteristic]] = [:]
    private var pendingWithoutResponseWrites: [PendingWrite] = []
    private var scanningRequested = false
    private var pendingConnection: UUID?

    override init() { super.init() }

    func prepare() { _ = central }

    func startScanning() {
        scanningRequested = true
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() { scanningRequested = false; central.stopScan() }

    func connect(identifier: UUID) {
        pendingConnection = identifier
        guard central.state == .poweredOn else { return }
        connectWhenReady(identifier)
    }

    private func connectWhenReady(_ identifier: UUID) {
        let peripheral = peripherals[identifier] ?? central.retrievePeripherals(withIdentifiers: [identifier]).first
        guard let peripheral else {
            pendingConnection = nil
            eventHandler?(.connectFailed(identifier, "未找到该设备，请重新扫描"))
            return
        }
        pendingConnection = nil
        peripherals[identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func disconnect(identifier: UUID) {
        pendingWithoutResponseWrites.removeAll { $0.identifier == identifier }
        guard let peripheral = peripherals[identifier] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func discoverServices(_ serviceUUIDs: [String], identifier: UUID) {
        peripherals[identifier]?.discoverServices(serviceUUIDs.map(CBUUID.init(string:)))
    }

    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, identifier: UUID) {
        guard let service = peripherals[identifier]?.services?.first(where: { normalize($0.uuid.uuidString) == normalize(serviceUUID) }) else {
            eventHandler?(.characteristics(identifier, service: serviceUUID, values: [], error: "服务不存在"))
            return
        }
        peripherals[identifier]?.discoverCharacteristics(characteristicUUIDs.map(CBUUID.init(string:)), for: service)
    }

    func setNotify(_ enabled: Bool, characteristicUUID: String, identifier: UUID) {
        guard let characteristic = characteristics[identifier]?[normalize(characteristicUUID)] else {
            eventHandler?(.notificationState(identifier, characteristic: characteristicUUID, enabled: false, error: "通知特征不存在"))
            return
        }
        peripherals[identifier]?.setNotifyValue(enabled, for: characteristic)
    }

    func write(_ data: Data, characteristicUUID: String, withResponse: Bool, identifier: UUID) throws {
        guard let peripheral = peripherals[identifier], peripheral.state == .connected else {
            throw BluetoothTransportError.disconnected
        }
        guard let characteristic = characteristics[identifier]?[normalize(characteristicUUID)] else {
            throw BluetoothTransportError.characteristicMissing
        }
        let writeType: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        let maximumLength = peripheral.maximumWriteValueLength(for: writeType)
        guard data.count <= maximumLength else {
            throw BluetoothTransportError.valueTooLong(actual: data.count, maximum: maximumLength)
        }

        if withResponse {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        } else if peripheral.canSendWriteWithoutResponse {
            submitWithoutResponse(data, characteristic: characteristic, peripheral: peripheral)
        } else {
            enqueueLatestWithoutResponse(data, characteristicUUID: characteristicUUID, identifier: identifier)
        }
    }

    private func enqueueLatestWithoutResponse(_ data: Data, characteristicUUID: String, identifier: UUID) {
        let normalizedUUID = normalize(characteristicUUID)
        pendingWithoutResponseWrites.removeAll {
            $0.identifier == identifier && normalize($0.characteristicUUID) == normalizedUUID
        }
        pendingWithoutResponseWrites.append(.init(data: data, characteristicUUID: characteristicUUID, identifier: identifier))
    }

    private func flushWithoutResponseWrites(for peripheral: CBPeripheral) {
        while peripheral.canSendWriteWithoutResponse,
              let index = pendingWithoutResponseWrites.firstIndex(where: { $0.identifier == peripheral.identifier }) {
            let pending = pendingWithoutResponseWrites.remove(at: index)
            guard let characteristic = characteristics[pending.identifier]?[normalize(pending.characteristicUUID)] else {
                eventHandler?(.writeCompleted(
                    pending.identifier,
                    characteristic: pending.characteristicUUID,
                    error: "写入特征不存在"
                ))
                continue
            }
            submitWithoutResponse(pending.data, characteristic: characteristic, peripheral: peripheral)
        }
    }

    private func submitWithoutResponse(_ data: Data, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        eventHandler?(.writeSubmitted(
            peripheral.identifier,
            characteristic: normalize(characteristic.uuid.uuidString)
        ))
    }

    private func normalize(_ uuid: String) -> String { CBUUID(string: uuid).uuidString.uppercased() }
}

extension CoreBluetoothTransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let availability: BluetoothAvailability = switch central.state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
        eventHandler?(.availability(availability))
        if central.state == .poweredOn {
            if scanningRequested { central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
            if let pendingConnection { connectWhenReady(pendingConnection) }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name,
              name == "AAAAA" || name.contains("br29") else { return }
        peripherals[peripheral.identifier] = peripheral
        eventHandler?(.discovered(.init(id: peripheral.identifier, name: name, rssi: RSSI.intValue, isConnected: peripheral.state == .connected)))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        eventHandler?(.connected(peripheral.identifier))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        eventHandler?(.connectFailed(peripheral.identifier, error?.localizedDescription ?? "连接失败"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        pendingWithoutResponseWrites.removeAll { $0.identifier == peripheral.identifier }
        characteristics[peripheral.identifier] = nil
        eventHandler?(.disconnected(peripheral.identifier, error?.localizedDescription))
    }
}

extension CoreBluetoothTransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        eventHandler?(.services(peripheral.identifier, peripheral.services?.map { normalize($0.uuid.uuidString) } ?? [], error?.localizedDescription))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let values: [BluetoothCharacteristic] = (service.characteristics ?? []).map { characteristic in
            let value = BluetoothCharacteristic(
                uuid: normalize(characteristic.uuid.uuidString),
                canWriteWithResponse: characteristic.properties.contains(.write),
                canWriteWithoutResponse: characteristic.properties.contains(.writeWithoutResponse),
                canNotify: characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            )
            characteristics[peripheral.identifier, default: [:]][value.uuid] = characteristic
            return value
        }
        eventHandler?(.characteristics(peripheral.identifier, service: normalize(service.uuid.uuidString), values: values, error: error?.localizedDescription))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        eventHandler?(.notificationState(peripheral.identifier, characteristic: normalize(characteristic.uuid.uuidString), enabled: characteristic.isNotifying, error: error?.localizedDescription))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        eventHandler?(.received(peripheral.identifier, characteristic: normalize(characteristic.uuid.uuidString), data: data))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        eventHandler?(.writeCompleted(peripheral.identifier, characteristic: normalize(characteristic.uuid.uuidString), error: error?.localizedDescription))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        flushWithoutResponseWrites(for: peripheral)
    }
}
