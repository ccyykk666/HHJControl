import Foundation
import XCTest
@testable import HHJControl

@MainActor
final class HHJBluetoothControllerTests: XCTestCase {
    func testReadyRequiresLocationCharacteristicAndExactAuthenticationResponse() {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(transport: transport, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let id = UUID()
        controller.connect(to: id)
        transport.send(.connected(id))
        transport.send(.services(id, [HHJProtocolConstants.dataService, HHJProtocolConstants.authService], nil))
        transport.send(.characteristics(id, service: HHJProtocolConstants.authService, values: [
            .init(uuid: HHJProtocolConstants.authWrite, canWriteWithResponse: true, canWriteWithoutResponse: false, canNotify: false),
            .init(uuid: HHJProtocolConstants.authNotify, canWriteWithResponse: false, canWriteWithoutResponse: false, canNotify: true)
        ], error: nil))
        XCTAssertFalse(controller.canSendLocation)
        transport.send(.characteristics(id, service: HHJProtocolConstants.dataService, values: [
            .init(uuid: HHJProtocolConstants.locationWrite, canWriteWithResponse: false, canWriteWithoutResponse: true, canNotify: false)
        ], error: nil))
        transport.send(.notificationState(id, characteristic: HHJProtocolConstants.authNotify, enabled: true, error: nil))
        XCTAssertFalse(controller.canSendLocation)
        XCTAssertTrue(transport.writes.contains { $0.characteristic == HHJProtocolConstants.authWrite && $0.withResponse })
        transport.send(.received(id, characteristic: HHJProtocolConstants.authNotify, data: Data("authSuc".utf8)))
        XCTAssertEqual(controller.state, .ready)
        XCTAssertTrue(controller.canSendLocation)
    }

    func testWrongAuthenticationResponseNeverEnablesLocation() {
        let (controller, transport, id) = makeDiscoveredController()
        transport.send(.received(id, characteristic: HHJProtocolConstants.authNotify, data: Data("authSuc\r\n".utf8)))
        XCTAssertFalse(controller.canSendLocation)
        if case .failed = controller.state {} else { XCTFail("Expected failed state") }
    }

    func testMissingLocationCharacteristicFailsClosed() {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(transport: transport, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let id = UUID()
        controller.connect(to: id)
        transport.send(.connected(id))
        transport.send(.services(id, [HHJProtocolConstants.authService, HHJProtocolConstants.dataService], nil))
        transport.send(.characteristics(id, service: HHJProtocolConstants.dataService, values: [], error: nil))
        XCTAssertFalse(controller.canSendLocation)
        if case .failed = controller.state {} else { XCTFail("Expected failed state") }
    }

    func testManualDisconnectDoesNotReconnect() {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(transport: transport, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let id = UUID()
        controller.connect(to: id)
        controller.disconnect()
        transport.send(.disconnected(id, nil))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(transport.connectCalls, [id])
    }

    private func makeDiscoveredController() -> (HHJBluetoothController, FakeBluetoothTransport, UUID) {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(transport: transport, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let id = UUID()
        controller.connect(to: id)
        transport.send(.connected(id))
        transport.send(.services(id, [HHJProtocolConstants.authService, HHJProtocolConstants.dataService], nil))
        transport.send(.characteristics(id, service: HHJProtocolConstants.authService, values: [
            .init(uuid: HHJProtocolConstants.authWrite, canWriteWithResponse: true, canWriteWithoutResponse: false, canNotify: false),
            .init(uuid: HHJProtocolConstants.authNotify, canWriteWithResponse: false, canWriteWithoutResponse: false, canNotify: true)
        ], error: nil))
        transport.send(.characteristics(id, service: HHJProtocolConstants.dataService, values: [
            .init(uuid: HHJProtocolConstants.locationWrite, canWriteWithResponse: false, canWriteWithoutResponse: true, canNotify: false)
        ], error: nil))
        transport.send(.notificationState(id, characteristic: HHJProtocolConstants.authNotify, enabled: true, error: nil))
        return (controller, transport, id)
    }
}

@MainActor
private final class FakeBluetoothTransport: BluetoothTransport {
    var eventHandler: ((BluetoothTransportEvent) -> Void)?
    var connectCalls: [UUID] = []
    var writes: [(data: Data, characteristic: String, withResponse: Bool)] = []
    func send(_ event: BluetoothTransportEvent) { eventHandler?(event) }
    func startScanning() {}
    func stopScanning() {}
    func connect(identifier: UUID) { connectCalls.append(identifier) }
    func disconnect(identifier: UUID) {}
    func discoverServices(_ serviceUUIDs: [String], identifier: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, identifier: UUID) {}
    func setNotify(_ enabled: Bool, characteristicUUID: String, identifier: UUID) {}
    func write(_ data: Data, characteristicUUID: String, withResponse: Bool, identifier: UUID) { writes.append((data, characteristicUUID, withResponse)) }
}
