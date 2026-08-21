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

    func testNotificationSubscriptionFailureFailsClosed() {
        let (controller, transport, id) = makeDiscoveredController(sendNotificationState: false)
        transport.send(.notificationState(id, characteristic: HHJProtocolConstants.authNotify, enabled: false, error: "notify rejected"))
        XCTAssertFalse(controller.canSendLocation)
        if case .failed(let message) = controller.state { XCTAssertTrue(message.contains("订阅认证通知失败")) }
        else { XCTFail("Expected failed state") }
    }

    func testAuthenticationWriteFailureFailsClosed() {
        let (controller, transport, id) = makeDiscoveredController()
        transport.send(.writeCompleted(id, characteristic: HHJProtocolConstants.authWrite, error: "write rejected"))
        XCTAssertFalse(controller.canSendLocation)
        if case .failed(let message) = controller.state { XCTAssertTrue(message.contains("写入")) }
        else { XCTFail("Expected failed state") }
    }

    func testAuthenticationTimeoutFailsClosed() {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(
            transport: transport,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            authenticationTimeout: .seconds(8),
            authenticationTimeoutScheduler: { _, action in action() }
        )
        let id = discover(controller: controller, transport: transport)
        transport.send(.notificationState(id, characteristic: HHJProtocolConstants.authNotify, enabled: true, error: nil))
        XCTAssertFalse(controller.canSendLocation)
        if case .failed(let message) = controller.state { XCTAssertTrue(message.contains("认证超时")) }
        else { XCTFail("Expected authentication timeout") }
    }

    func testAutomaticReconnectStopsAfterFiveAttempts() {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(
            transport: transport,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            reconnectDelay: { _ in .zero },
            reconnectScheduler: { _, action in action() }
        )
        let id = UUID()
        controller.connect(to: id)
        for _ in 0..<5 {
            transport.send(.connectFailed(id, "offline"))
        }
        transport.send(.connectFailed(id, "offline"))
        XCTAssertEqual(transport.connectCalls.count, 6, "one manual attempt plus five bounded reconnects")
        if case .failed(let message) = controller.state { XCTAssertTrue(message.contains("5 次")) }
        else { XCTFail("Expected reconnect exhaustion") }
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

    private func makeDiscoveredController(sendNotificationState: Bool = true) -> (HHJBluetoothController, FakeBluetoothTransport, UUID) {
        let transport = FakeBluetoothTransport()
        let controller = HHJBluetoothController(transport: transport, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let id = discover(controller: controller, transport: transport)
        if sendNotificationState { transport.send(.notificationState(id, characteristic: HHJProtocolConstants.authNotify, enabled: true, error: nil)) }
        return (controller, transport, id)
    }

    private func discover(controller: HHJBluetoothController, transport: FakeBluetoothTransport) -> UUID {
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
        return id
    }
}

@MainActor
private final class FakeBluetoothTransport: BluetoothTransport {
    var eventHandler: ((BluetoothTransportEvent) -> Void)?
    var connectCalls: [UUID] = []
    var writes: [(data: Data, characteristic: String, withResponse: Bool)] = []
    func send(_ event: BluetoothTransportEvent) { eventHandler?(event) }
    func prepare() {}
    func startScanning() {}
    func stopScanning() {}
    func connect(identifier: UUID) { connectCalls.append(identifier) }
    func disconnect(identifier: UUID) {}
    func discoverServices(_ serviceUUIDs: [String], identifier: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String], serviceUUID: String, identifier: UUID) {}
    func setNotify(_ enabled: Bool, characteristicUUID: String, identifier: UUID) {}
    func write(_ data: Data, characteristicUUID: String, withResponse: Bool, identifier: UUID) { writes.append((data, characteristicUUID, withResponse)) }
}
