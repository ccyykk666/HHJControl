import Foundation
import SwiftUI

struct DeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: HHJBluetoothController

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("选择设备").font(.headline)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("关闭")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        bluetooth.state.title,
                        systemImage: bluetooth.canSendLocation ? "checkmark.seal.fill" : "antenna.radiowaves.left.and.right"
                    )
                    .font(.headline)
                    .foregroundStyle(bluetooth.canSendLocation ? .green : .primary)

                    if bluetooth.connectedIdentifier != nil {
                        Divider()
                        HStack {
                            Button("断开", role: .destructive) { bluetooth.disconnect() }
                            if !bluetooth.canSendLocation {
                                Button("重新认证") { bluetooth.retryAuthentication() }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !bluetooth.canSendLocation {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("设备列表").font(.headline)
                        Divider()

                        if bluetooth.devices.isEmpty {
                            HStack {
                                ProgressView().opacity(bluetooth.state == .scanning ? 1 : 0)
                                Text(bluetooth.state == .scanning ? "正在查找设备…" : "暂未发现设备")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(bluetooth.devices) { device in
                                        Button {
                                            bluetooth.connect(to: device.id)
                                        } label: {
                                            HStack {
                                                Text(device.name).foregroundStyle(.primary)
                                                Spacer()
                                                Text("\(device.rssi) dBm")
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 11)
                                        }
                                        if device.id != bluetooth.devices.last?.id { Divider() }
                                    }
                                }
                            }
                            .frame(maxHeight: 280)
                        }

                        if bluetooth.state != .scanning {
                            Divider()
                            Button("重新扫描") { bluetooth.startScanning() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(presentationHeight)])
        .onAppear(perform: beginScanningIfNeeded)
        .onChange(of: bluetooth.state) { _, state in
            if state == .ready { dismiss() }
        }
    }

    private func beginScanningIfNeeded() {
        switch bluetooth.state {
        case .scanning, .connecting, .discovering, .authenticating, .ready, .reconnecting:
            break
        case .idle, .bluetoothUnavailable, .failed:
            bluetooth.startScanning()
        }
    }

    private var presentationHeight: CGFloat {
        guard !bluetooth.canSendLocation else { return 220 }

        let visibleRows = max(1, min(bluetooth.devices.count, 6))
        let rescanControlHeight: CGFloat = bluetooth.state == .scanning ? 0 : 48
        return min(600, 230 + CGFloat(visibleRows) * 45 + rescanControlHeight)
    }
}

struct AdvancedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("手动定位") {
                    LabeledContent("纬度", value: String(format: "%.6f", model.selection.wgs84Latitude))
                    LabeledContent("经度", value: String(format: "%.6f", model.selection.wgs84Longitude))
                    LabeledContent("海拔", value: String(format: "%.1f m", model.selection.altitude))
                    Button("设置经纬度与海拔") { showEditor = true }
                }

                Section("设备") {
                    LabeledContent("连接状态", value: bluetooth.state.title)
                    if bluetooth.connectedIdentifier != nil {
                        Button("断开连接", role: .destructive) { bluetooth.disconnect() }
                        if !bluetooth.canSendLocation {
                            Button("重新认证") { bluetooth.retryAuthentication() }
                        }
                    }
                }

                Section("设置") {
                    NavigationLink {
                        ShortcutView()
                    } label: {
                        Label("快捷指令", systemImage: "wand.and.stars")
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("权限、隐私与关于", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("高级")
            .sheet(isPresented: $showEditor) {
                CoordinateEditorView(
                    selection: $model.selection,
                    mapCoordinateReference: model.mapCoordinateReference
                ) {
                    model.refreshSelectionDetails()
                    model.mapRequestID = UUID()
                    model.selectedTab = .location
                }
            }
        }
    }
}

private struct ShortcutView: View {
    private enum State: Equatable {
        case readyForFirst
        case waitingForFirst
        case countdown(Int)
        case readyForSecond
        case waitingForSecond
        case completed
        case failed
    }

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: AppModel
    @State private var state: State = .readyForFirst
    @State private var stateTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Button(action: performAction) {
                    HStack(spacing: 12) {
                        Label(buttonTitle, systemImage: buttonIcon)
                        Spacer()
                        if showsProgress {
                            ProgressView()
                        }
                    }
                }
                .disabled(!isActionEnabled)
            }
        }
        .navigationTitle("快捷指令")
        .onChange(of: model.shortcutCallback) { _, callback in
            handleCallback(callback)
        }
    }

    private var buttonTitle: String {
        switch state {
        case .readyForFirst: "打开 HHJ1"
        case .waitingForFirst: "正在打开 HHJ1…"
        case .countdown(let seconds): "等待 \(seconds) 秒…"
        case .readyForSecond: "打开 HHJ2"
        case .waitingForSecond: "正在打开 HHJ2…"
        case .completed: "已完成"
        case .failed: "操作失败"
        }
    }

    private var buttonIcon: String {
        switch state {
        case .readyForFirst, .waitingForFirst: "airplane"
        case .countdown: "timer"
        case .readyForSecond, .waitingForSecond: "location.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var showsProgress: Bool {
        switch state {
        case .waitingForFirst, .countdown, .waitingForSecond: true
        default: false
        }
    }

    private var isActionEnabled: Bool {
        switch state {
        case .readyForFirst, .readyForSecond: true
        default: false
        }
    }

    private func performAction() {
        switch state {
        case .readyForFirst:
            state = .waitingForFirst
            openShortcut(named: "HHJ1", stage: .hhj1)
        case .readyForSecond:
            state = .waitingForSecond
            openShortcut(named: "HHJ2", stage: .hhj2)
        default:
            break
        }
    }

    private func handleCallback(_ callback: AppModel.ShortcutCallback?) {
        guard let callback else { return }
        switch (callback.stage, callback.result) {
        case (.hhj1, .success):
            startCountdown()
        case (.hhj2, .success):
            showTemporaryState(.completed)
        case (_, .cancelled), (_, .failed):
            showTemporaryState(.failed)
        }
    }

    private func startCountdown() {
        stateTask?.cancel()
        stateTask = Task { @MainActor in
            do {
                for seconds in stride(from: 10, through: 1, by: -1) {
                    state = .countdown(seconds)
                    try await Task.sleep(for: .seconds(1))
                }
                state = .readyForSecond
            } catch {
                state = .readyForFirst
            }
        }
    }

    private func showTemporaryState(_ value: State) {
        stateTask?.cancel()
        stateTask = Task { @MainActor in
            state = value
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { state = .readyForFirst }
        }
    }

    private func openShortcut(named name: String, stage: AppModel.ShortcutCallback.Stage) {
        guard let url = shortcutURL(named: name, stage: stage) else {
            showTemporaryState(.failed)
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in
                    showTemporaryState(.failed)
                }
            }
        }
    }

    private func shortcutURL(named name: String, stage: AppModel.ShortcutCallback.Stage) -> URL? {
        func callbackURL(result: AppModel.ShortcutCallback.Result) -> String? {
            var callback = URLComponents()
            callback.scheme = "hhjcontrol"
            callback.host = "shortcut-return"
            callback.queryItems = [
                URLQueryItem(name: "stage", value: stage.rawValue),
                URLQueryItem(name: "result", value: result.rawValue)
            ]
            return callback.url?.absoluteString
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: callbackURL(result: .success)),
            URLQueryItem(name: "x-cancel", value: callbackURL(result: .cancelled)),
            URLQueryItem(name: "x-error", value: callbackURL(result: .failed))
        ]
        return components.url
    }
}
