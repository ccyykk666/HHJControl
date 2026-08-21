import Foundation

enum BluetoothAvailability: Equatable, Sendable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

struct BluetoothCharacteristic: Equatable, Sendable {
    var uuid: String
    var canWriteWithResponse: Bool
    var canWriteWithoutResponse: Bool
    var canNotify: Bool
}

enum BluetoothTransportEvent: Sendable {
    case availability(BluetoothAvailability)
    case discovered(DiscoveredDevice)
    case connected(UUID)
    case connectFailed(UUID, String)
    case disconnected(UUID, String?)
    case services(UUID, [String], String?)
    case characteristics(UUID, service: String, values: [BluetoothCharacteristic], error: String?)
    case notificationState(UUID, characteristic: String, enabled: Bool, error: String?)
    case received(UUID, characteristic: String, data: Data)
    case writeCompleted(UUID, characteristic: String, error: String?)
}

@MainActor
protocol BluetoothTransport: AnyObject {
    var eventHandler: ((BluetoothTransportEvent) -> Void)? { get set }
    func prepare()
    func startScanning()
    func stopScanning()
    func connect(identifier: UUID)
    func disconnect(identifier: UUID)
    func discoverServices(_ serviceUUIDs: [String], identifier: UUID)
    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, identifier: UUID)
    func setNotify(_ enabled: Bool, characteristicUUID: String, identifier: UUID)
    func write(_ data: Data, characteristicUUID: String, withResponse: Bool, identifier: UUID)
}

/// Keeps hosted unit tests from creating CBCentralManager and triggering a system permission alert.
@MainActor
final class InactiveBluetoothTransport: BluetoothTransport {
    var eventHandler: ((BluetoothTransportEvent) -> Void)?
    func prepare() {}
    func startScanning() {}
    func stopScanning() {}
    func connect(identifier: UUID) {}
    func disconnect(identifier: UUID) {}
    func discoverServices(_ serviceUUIDs: [String], identifier: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, identifier: UUID) {}
    func setNotify(_ enabled: Bool, characteristicUUID: String, identifier: UUID) {}
    func write(_ data: Data, characteristicUUID: String, withResponse: Bool, identifier: UUID) {}
}
