import Foundation
import SwiftUI

@MainActor
final class HHJBluetoothController: ObservableObject {
    enum State: Equatable {
        case idle, scanning, connecting, discovering, authenticating, ready, reconnecting(attempt: Int), bluetoothUnavailable(String), failed(String)

        var title: String {
            switch self {
            case .idle: "未连接"
            case .scanning: "正在扫描"
            case .connecting: "正在连接"
            case .discovering: "正在识别设备"
            case .authenticating: "正在认证"
            case .ready: "HHJ 已就绪"
            case .reconnecting(let attempt): "正在重连（\(attempt)/5）"
            case .bluetoothUnavailable: "蓝牙不可用"
            case .failed: "连接失败"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var logs: [CommunicationLog] = []

    var canSendLocation: Bool { state == .ready && locationCharacteristicFound && authenticated }
    var connectedIdentifier: UUID? { activeIdentifier }

    private let transport: BluetoothTransport
    private let defaults: UserDefaults
    private var activeIdentifier: UUID?
    private var servicesFound = Set<String>()
    private var characteristicsFound = Set<String>()
    private var locationCharacteristicFound = false
    private var authenticated = false
    private var manualDisconnect = false
    private var isForeground = true
    private var reconnectAttempt = 0
    private var authenticationToken = UUID()

    init(transport: BluetoothTransport, defaults: UserDefaults = .standard) {
        self.transport = transport
        self.defaults = defaults
        transport.eventHandler = { [weak self] event in self?.handle(event) }
    }

    convenience init() { self.init(transport: CoreBluetoothTransport()) }

    func startScanning() {
        resetSession(keepingIdentifier: false)
        manualDisconnect = false
        state = .scanning
        log(.info, "开始扫描所有 BLE 外设")
        transport.startScanning()
    }

    func stopScanning() {
        transport.stopScanning()
        if state == .scanning { state = .idle }
    }

    func connect(to identifier: UUID) {
        transport.stopScanning()
        resetSession(keepingIdentifier: false)
        activeIdentifier = identifier
        manualDisconnect = false
        state = .connecting
        log(.info, "连接设备 \(identifier.uuidString)")
        transport.connect(identifier: identifier)
    }

    func disconnect() {
        manualDisconnect = true
        authenticationToken = UUID()
        if let activeIdentifier { transport.disconnect(identifier: activeIdentifier) }
        resetSession(keepingIdentifier: false)
        state = .idle
        log(.info, "已手动断开；不会自动重连")
    }

    func retryAuthentication() {
        guard let identifier = activeIdentifier,
              locationCharacteristicFound,
              characteristicsFound.contains(normalize(HHJProtocolConstants.authWrite)),
              characteristicsFound.contains(normalize(HHJProtocolConstants.authNotify)) else {
            fail("认证特征尚未就绪")
            return
        }
        authenticated = false
        state = .authenticating
        log(.info, "重新订阅认证通知")
        transport.setNotify(true, characteristicUUID: HHJProtocolConstants.authNotify, identifier: identifier)
    }

    func sendLocation(_ selection: LocationSelection, date: Date = Date()) throws {
        guard canSendLocation, let identifier = activeIdentifier else { throw ControllerError.notReady }
        let payload = try HHJPacketEncoder.locationPayload(selection: selection, date: date)
        transport.write(payload, characteristicUUID: HHJProtocolConstants.locationWrite, withResponse: false, identifier: identifier)
        log(.success, "TX 定位数据 \(payload.count) 字节 → 32E1")
    }

    func setForeground(_ value: Bool) {
        isForeground = value
        if value, activeIdentifier == nil, let raw = defaults.string(forKey: "lastPeripheralIdentifier"), let identifier = UUID(uuidString: raw), !manualDisconnect {
            reconnectAttempt = 0
            scheduleReconnect(identifier)
        }
    }

    func copyableDiagnostics() -> String {
        logs.map { "[\($0.date.formatted(date: .numeric, time: .standard))] \($0.level.rawValue) \($0.message)" }.joined(separator: "\n")
    }

    private func handle(_ event: BluetoothTransportEvent) {
        switch event {
        case .availability(let availability):
            handleAvailability(availability)
        case .discovered(let device):
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device } else { devices.append(device) }
            devices.sort { $0.rssi > $1.rssi }
        case .connected(let identifier):
            guard identifier == activeIdentifier else { return }
            reconnectAttempt = 0
            defaults.set(identifier.uuidString, forKey: "lastPeripheralIdentifier")
            state = .discovering
            log(.success, "已连接；发现 HHJ 服务")
            transport.discoverServices([HHJProtocolConstants.authService, HHJProtocolConstants.dataService], identifier: identifier)
        case .connectFailed(let identifier, let message):
            guard identifier == activeIdentifier else { return }
            log(.error, "连接失败：\(message)")
            reconnectOrFail(identifier)
        case .disconnected(let identifier, let message):
            guard identifier == activeIdentifier else { return }
            authenticated = false
            locationCharacteristicFound = false
            log(.warning, "连接断开\(message.map { "：\($0)" } ?? "")")
            if manualDisconnect { resetSession(keepingIdentifier: false); state = .idle } else { reconnectOrFail(identifier) }
        case .services(let identifier, let services, let error):
            guard identifier == activeIdentifier else { return }
            guard error == nil else { fail("发现服务失败：\(error!)"); return }
            servicesFound = Set(services.map(normalize))
            let authService = normalize(HHJProtocolConstants.authService)
            let dataService = normalize(HHJProtocolConstants.dataService)
            guard servicesFound.contains(authService), servicesFound.contains(dataService) else { fail("不是兼容的 HHJ 设备：缺少服务 UUID"); return }
            log(.info, "已找到服务 FAA1 与 FBB2")
            transport.discoverCharacteristics([HHJProtocolConstants.authWrite, HHJProtocolConstants.authNotify], serviceUUID: HHJProtocolConstants.authService, identifier: identifier)
            transport.discoverCharacteristics([HHJProtocolConstants.locationWrite], serviceUUID: HHJProtocolConstants.dataService, identifier: identifier)
        case .characteristics(let identifier, let service, let values, let error):
            guard identifier == activeIdentifier else { return }
            guard error == nil else { fail("发现特征失败：\(error!)"); return }
            for value in values { characteristicsFound.insert(normalize(value.uuid)) }
            if normalize(service) == normalize(HHJProtocolConstants.dataService) {
                guard let location = values.first(where: { normalize($0.uuid) == normalize(HHJProtocolConstants.locationWrite) }), location.canWriteWithoutResponse else {
                    fail("定位特征 32E1 缺失或不支持无响应写入"); return
                }
                locationCharacteristicFound = true
                log(.info, "定位特征 32E1 已就绪")
            }
            beginAuthenticationIfPossible(identifier)
        case .notificationState(let identifier, let characteristic, let enabled, let error):
            guard identifier == activeIdentifier, normalize(characteristic) == normalize(HHJProtocolConstants.authNotify) else { return }
            guard error == nil, enabled else { fail("订阅认证通知失败：\(error ?? "设备拒绝通知")"); return }
            state = .authenticating
            let payload = HHJPacketEncoder.authPayload(at: Date())
            log(.info, "TX 认证 \(payload.count) 字节：<Unix秒>_••••••••")
            transport.write(payload, characteristicUUID: HHJProtocolConstants.authWrite, withResponse: true, identifier: identifier)
            startAuthenticationTimeout()
        case .received(let identifier, let characteristic, let data):
            guard identifier == activeIdentifier else { return }
            log(.info, "RX \(data.count) 字节 ← \(shortUUID(characteristic))")
            guard normalize(characteristic) == normalize(HHJProtocolConstants.authNotify) else { return }
            guard String(data: data, encoding: .utf8) == HHJProtocolConstants.authSuccess else { fail("认证响应不匹配"); return }
            authenticationToken = UUID()
            authenticated = true
            if locationCharacteristicFound {
                state = .ready
                log(.success, "认证成功；定位发送已启用")
            }
        case .writeCompleted(let identifier, let characteristic, let error):
            guard identifier == activeIdentifier else { return }
            if let error { fail("写入 \(shortUUID(characteristic)) 失败：\(error)") }
            else { log(.info, "写入 \(shortUUID(characteristic)) 已确认") }
        }
    }

    private func beginAuthenticationIfPossible(_ identifier: UUID) {
        let write = normalize(HHJProtocolConstants.authWrite)
        let notify = normalize(HHJProtocolConstants.authNotify)
        guard locationCharacteristicFound, characteristicsFound.contains(write), characteristicsFound.contains(notify), !authenticated, state != .authenticating else { return }
        state = .authenticating
        log(.info, "订阅认证通知 21E2")
        transport.setNotify(true, characteristicUUID: HHJProtocolConstants.authNotify, identifier: identifier)
    }

    private func startAuthenticationTimeout() {
        let token = UUID()
        authenticationToken = token
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.authenticationToken == token, !self.authenticated else { return }
            self.fail("认证超时，请重新认证")
        }
    }

    private func handleAvailability(_ availability: BluetoothAvailability) {
        switch availability {
        case .poweredOn:
            log(.info, "蓝牙已开启")
        case .poweredOff: state = .bluetoothUnavailable("请在系统设置中开启蓝牙")
        case .unauthorized: state = .bluetoothUnavailable("未获得蓝牙权限，请前往设置授权")
        case .unsupported: state = .bluetoothUnavailable("此设备不支持低功耗蓝牙")
        case .unknown, .resetting: state = .bluetoothUnavailable("蓝牙正在初始化")
        }
    }

    private func reconnectOrFail(_ identifier: UUID) {
        authenticated = false
        locationCharacteristicFound = false
        guard isForeground, !manualDisconnect, reconnectAttempt < 5 else {
            fail(reconnectAttempt >= 5 ? "自动重连已达到 5 次" : "连接已断开")
            return
        }
        scheduleReconnect(identifier)
    }

    private func scheduleReconnect(_ identifier: UUID) {
        activeIdentifier = identifier
        reconnectAttempt += 1
        let delay = reconnectAttempt
        state = .reconnecting(attempt: reconnectAttempt)
        log(.info, "将在 \(delay) 秒后重连")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isForeground, !self.manualDisconnect, self.activeIdentifier == identifier else { return }
            self.state = .connecting
            self.transport.connect(identifier: identifier)
        }
    }

    private func resetSession(keepingIdentifier: Bool) {
        authenticationToken = UUID()
        servicesFound.removeAll()
        characteristicsFound.removeAll()
        locationCharacteristicFound = false
        authenticated = false
        if !keepingIdentifier { activeIdentifier = nil }
    }

    private func fail(_ message: String) {
        authenticationToken = UUID()
        authenticated = false
        state = .failed(message)
        log(.error, message)
    }

    private func log(_ level: CommunicationLog.Level, _ message: String) {
        logs.append(.init(level: level, message: message))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    private func normalize(_ uuid: String) -> String { uuid.uppercased() }
    private func shortUUID(_ uuid: String) -> String { String(normalize(uuid).prefix(8)) }

    enum ControllerError: LocalizedError {
        case notReady
        var errorDescription: String? { "HHJ 尾插尚未认证就绪" }
    }
}
