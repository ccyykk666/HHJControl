import Foundation
import SwiftUI

@MainActor
final class HHJBluetoothController: ObservableObject {
    typealias AuthenticationTimeoutAction = @MainActor @Sendable () -> Void
    typealias ReconnectAction = @MainActor @Sendable () -> Void
    enum State: Equatable {
        case idle, scanning, connecting, discovering, authenticating, ready, reconnecting(attempt: Int), bluetoothUnavailable(String), failed(String)

        var title: String {
            switch self {
            case .idle: "未连接"
            case .scanning: "正在扫描"
            case .connecting: "正在连接"
            case .discovering: "正在识别设备"
            case .authenticating: "正在认证"
            case .ready: "设备已就绪"
            case .reconnecting: "正在重连"
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
    var canRetryAuthentication: Bool {
        activeIdentifier != nil &&
        locationCharacteristicFound &&
        characteristicsFound.contains(normalize(HHJProtocolConstants.authWrite)) &&
        characteristicsFound.contains(normalize(HHJProtocolConstants.authNotify))
    }

    private let transport: BluetoothTransport
    private let defaults: UserDefaults
    private let authenticationTimeout: Duration
    private let reconnectDelay: (Int) -> Duration
    private let reconnectTimeout: Duration
    private let authenticationTimeoutScheduler: (Duration, @escaping AuthenticationTimeoutAction) -> Void
    private let reconnectScheduler: (Duration, @escaping ReconnectAction) -> Void
    private var activeIdentifier: UUID?
    private var servicesFound = Set<String>()
    private var characteristicsFound = Set<String>()
    private var locationCharacteristicFound = false
    private var authenticated = false
    private var manualDisconnect = false
    private var reconnectAttempt = 0
    private var reconnectTimeoutToken = UUID()
    private var reconnectTimeoutIdentifier: UUID?
    private var authenticationToken = UUID()
    private var availability: BluetoothAvailability = .unknown
    private var authWriteReady = false
    private var authNotifyReady = false
    private var locationStreamingTask: Task<Void, Never>?

    init(
        transport: BluetoothTransport,
        defaults: UserDefaults = .standard,
        authenticationTimeout: Duration = .seconds(8),
        reconnectDelay: @escaping (Int) -> Duration = { .seconds($0) },
        reconnectTimeout: Duration = .seconds(60),
        authenticationTimeoutScheduler: ((Duration, @escaping AuthenticationTimeoutAction) -> Void)? = nil,
        reconnectScheduler: ((Duration, @escaping ReconnectAction) -> Void)? = nil
    ) {
        self.transport = transport
        self.defaults = defaults
        self.authenticationTimeout = authenticationTimeout
        self.reconnectDelay = reconnectDelay
        self.reconnectTimeout = reconnectTimeout
        self.authenticationTimeoutScheduler = authenticationTimeoutScheduler ?? { duration, action in
            Task { @MainActor in
                try? await Task.sleep(for: duration)
                action()
            }
        }
        self.reconnectScheduler = reconnectScheduler ?? { duration, action in
            Task { @MainActor in
                try? await Task.sleep(for: duration)
                action()
            }
        }
        transport.eventHandler = { [weak self] event in self?.handle(event) }
    }

    convenience init() { self.init(transport: CoreBluetoothTransport()) }

    func requestAuthorization() {
        transport.prepare()
    }

    func startScanning() {
        guard availability == .poweredOn || availability == .unknown else {
            state = .bluetoothUnavailable(availabilityMessage)
            return
        }
        resetSession(keepingIdentifier: false)
        clearReconnectTimeout()
        reconnectAttempt = 0
        manualDisconnect = false
        devices.removeAll()
        state = .scanning
        log(.info, "开始扫描设备")
        transport.startScanning()
    }

    func stopScanning() {
        transport.stopScanning()
        if state == .scanning { state = .idle }
    }

    func connect(to identifier: UUID) {
        transport.stopScanning()
        resetSession(keepingIdentifier: false)
        clearReconnectTimeout()
        reconnectAttempt = 0
        activeIdentifier = identifier
        manualDisconnect = false
        startReconnectTimeout(identifier)
        state = .connecting
        log(.info, "连接设备 \(identifier.uuidString)")
        transport.connect(identifier: identifier)
    }

    func disconnect() {
        manualDisconnect = true
        stopLocationStreaming()
        authenticationToken = UUID()
        clearReconnectTimeout()
        if let activeIdentifier { transport.disconnect(identifier: activeIdentifier) }
        resetSession(keepingIdentifier: false)
        devices.removeAll()
        state = .idle
        log(.info, "已手动断开；不会自动重连")
    }

    func retryAuthentication() {
        guard let identifier = activeIdentifier, canRetryAuthentication else {
            fail("认证特征尚未就绪")
            return
        }
        authenticated = false
        state = .authenticating
        log(.info, "重新订阅认证通知")
        transport.setNotify(true, characteristicUUID: HHJProtocolConstants.authNotify, identifier: identifier)
    }

    func sendLocation(_ selection: LocationSelection, date: Date = Date()) throws {
        try writeLocation(selection, date: date, logSubmission: true)
    }

    private func writeLocation(_ selection: LocationSelection, date: Date, logSubmission: Bool) throws {
        guard canSendLocation, let identifier = activeIdentifier else { throw ControllerError.notReady }
        let payload = try HHJPacketEncoder.locationPayload(selection: selection, date: date)
        try transport.write(payload, characteristicUUID: HHJProtocolConstants.locationWrite, withResponse: false, identifier: identifier)
        if logSubmission {
            log(.info, "定位指令 \(payload.count) 字节已进入发送流程 → 32E1")
        }
    }

    func startLocationStreaming(_ selection: LocationSelection) throws {
        locationStreamingTask?.cancel()
        try sendLocation(selection)
        log(.success, "已开始持续发送定位数据")
        locationStreamingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                guard self.canSendLocation else { continue }
                do {
                    try self.writeLocation(selection, date: Date(), logSubmission: false)
                } catch {
                    self.log(.warning, "持续发送暂未完成：\(error.localizedDescription)")
                }
            }
        }
    }

    private func stopLocationStreaming() {
        locationStreamingTask?.cancel()
        locationStreamingTask = nil
    }

    func setForeground(_ value: Bool) {
        if value, activeIdentifier == nil, let raw = defaults.string(forKey: "lastPeripheralIdentifier"), let identifier = UUID(uuidString: raw), !manualDisconnect {
            reconnectAttempt = 0
            startReconnectTimeout(identifier)
            scheduleReconnect(identifier)
        }
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
            clearReconnectTimeout()
            reconnectAttempt = 0
            defaults.set(identifier.uuidString, forKey: "lastPeripheralIdentifier")
            state = .discovering
            log(.success, "已连接；正在发现设备服务")
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
            guard servicesFound.contains(authService), servicesFound.contains(dataService) else { fail("不是兼容设备：缺少服务 UUID"); return }
            log(.info, "已找到服务 FAA1 与 FBB2")
            transport.discoverCharacteristics([HHJProtocolConstants.authWrite, HHJProtocolConstants.authNotify], serviceUUID: HHJProtocolConstants.authService, identifier: identifier)
            transport.discoverCharacteristics([HHJProtocolConstants.locationWrite], serviceUUID: HHJProtocolConstants.dataService, identifier: identifier)
        case .characteristics(let identifier, let service, let values, let error):
            guard identifier == activeIdentifier else { return }
            guard error == nil else { fail("发现特征失败：\(error!)"); return }
            for value in values { characteristicsFound.insert(normalize(value.uuid)) }
            if normalize(service) == normalize(HHJProtocolConstants.authService) {
                guard let write = values.first(where: { normalize($0.uuid) == normalize(HHJProtocolConstants.authWrite) }), write.canWriteWithResponse else {
                    fail("认证写入特征 21E1 缺失或不支持响应写入"); return
                }
                guard let notify = values.first(where: { normalize($0.uuid) == normalize(HHJProtocolConstants.authNotify) }), notify.canNotify else {
                    fail("认证通知特征 21E2 缺失或不支持通知"); return
                }
                authWriteReady = true
                authNotifyReady = true
                log(.info, "认证特征 21E1 与 21E2 已就绪")
            } else if normalize(service) == normalize(HHJProtocolConstants.dataService) {
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
            do {
                try transport.write(payload, characteristicUUID: HHJProtocolConstants.authWrite, withResponse: true, identifier: identifier)
            } catch {
                fail("认证写入失败：\(error.localizedDescription)")
                return
            }
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
        case .writeSubmitted(let identifier, _):
            guard identifier == activeIdentifier else { return }
        case .writeCompleted(let identifier, let characteristic, let error):
            guard identifier == activeIdentifier else { return }
            if let error { fail("写入 \(shortUUID(characteristic)) 失败：\(error)") }
            else { log(.info, "写入 \(shortUUID(characteristic)) 已确认") }
        }
    }

    private func beginAuthenticationIfPossible(_ identifier: UUID) {
        let write = normalize(HHJProtocolConstants.authWrite)
        let notify = normalize(HHJProtocolConstants.authNotify)
        guard locationCharacteristicFound, authWriteReady, authNotifyReady, characteristicsFound.contains(write), characteristicsFound.contains(notify), !authenticated, state != .authenticating else { return }
        state = .authenticating
        log(.info, "订阅认证通知 21E2")
        transport.setNotify(true, characteristicUUID: HHJProtocolConstants.authNotify, identifier: identifier)
    }

    private func startAuthenticationTimeout() {
        let token = UUID()
        authenticationToken = token
        authenticationTimeoutScheduler(authenticationTimeout) { [weak self] in
            guard let self, self.authenticationToken == token, !self.authenticated else { return }
            self.fail("认证超时，请重新认证")
        }
    }

    private func handleAvailability(_ availability: BluetoothAvailability) {
        self.availability = availability
        switch availability {
        case .poweredOn:
            if case .bluetoothUnavailable = state { state = .idle }
            log(.info, "蓝牙已开启")
        case .poweredOff: state = .bluetoothUnavailable("请在系统设置中开启蓝牙")
        case .unauthorized: state = .bluetoothUnavailable("未获得蓝牙权限，请前往设置授权")
        case .unsupported: state = .bluetoothUnavailable("此设备不支持低功耗蓝牙")
        case .unknown, .resetting: state = .bluetoothUnavailable("蓝牙正在初始化")
        }
    }

    private func reconnectOrFail(_ identifier: UUID) {
        resetSession(keepingIdentifier: true)
        guard !manualDisconnect else { fail("连接已断开"); return }
        startReconnectTimeout(identifier)
        scheduleReconnect(identifier)
    }

    private func startReconnectTimeout(_ identifier: UUID) {
        guard reconnectTimeoutIdentifier != identifier else { return }
        let token = UUID()
        reconnectTimeoutToken = token
        reconnectTimeoutIdentifier = identifier
        authenticationTimeoutScheduler(reconnectTimeout) { [weak self] in
            guard let self,
                  self.reconnectTimeoutToken == token,
                  self.reconnectTimeoutIdentifier == identifier,
                  self.activeIdentifier == identifier else { return }
            self.resetSession(keepingIdentifier: false)
            self.clearReconnectTimeout()
            self.state = .failed("连接失败")
        }
    }

    private func clearReconnectTimeout() {
        reconnectTimeoutToken = UUID()
        reconnectTimeoutIdentifier = nil
    }

    private func scheduleReconnect(_ identifier: UUID) {
        activeIdentifier = identifier
        reconnectAttempt += 1
        let delay = reconnectAttempt
        let duration = reconnectDelay(delay)
        state = .reconnecting(attempt: reconnectAttempt)
        log(.info, "将在 \(delay) 秒后重连")
        reconnectScheduler(duration) { [weak self] in
            guard let self, !self.manualDisconnect, self.activeIdentifier == identifier else { return }
            self.state = .connecting
            self.transport.connect(identifier: identifier)
        }
    }

    private func resetSession(keepingIdentifier: Bool) {
        authenticationToken = UUID()
        servicesFound.removeAll()
        characteristicsFound.removeAll()
        locationCharacteristicFound = false
        authWriteReady = false
        authNotifyReady = false
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

    private var availabilityMessage: String {
        switch availability {
        case .poweredOff: "请在系统设置中开启蓝牙"
        case .unauthorized: "未获得蓝牙权限，请前往设置授权"
        case .unsupported: "此设备不支持低功耗蓝牙"
        case .unknown, .resetting: "蓝牙正在初始化"
        case .poweredOn: "蓝牙可用"
        }
    }

    enum ControllerError: LocalizedError {
        case notReady
        var errorDescription: String? { "设备尚未认证就绪" }
    }
}
