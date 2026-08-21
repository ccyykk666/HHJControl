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
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(
                        bluetooth.canSendLocation ? "设备已连接" : bluetooth.state.title,
                        systemImage: bluetooth.canSendLocation ? "checkmark.seal.fill" : "antenna.radiowaves.left.and.right"
                    )
                    .font(.headline)
                    .foregroundStyle(bluetooth.canSendLocation ? .green : .primary)

                    Spacer()

                    if bluetooth.connectedIdentifier != nil {
                        Button("断开", role: .destructive) { bluetooth.disconnect() }
                        if case .failed = bluetooth.state, bluetooth.canRetryAuthentication {
                            Button("重新认证") { bluetooth.retryAuthentication() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !bluetooth.canSendLocation {
                    Divider()
                        .padding(.vertical, 20)

                    Text("设备列表").font(.headline)

                    if bluetooth.devices.isEmpty {
                        HStack {
                            if bluetooth.state == .scanning {
                                ProgressView()
                            }
                            Text(bluetooth.state == .scanning ? "正在查找设备…" : "暂未发现设备")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if bluetooth.state != .scanning {
                                Button("重新扫描") { bluetooth.startScanning() }
                            }
                        }
                        .padding(.top, 16)
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
                        .padding(.top, 12)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(presentationHeight)])
        .onAppear(perform: beginScanningIfNeeded)
        .onChange(of: bluetooth.state) { _, state in
            guard state == .ready else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_500))
                if bluetooth.state == .ready { dismiss() }
            }
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
        return min(600, 190 + CGFloat(visibleRows) * 45)
    }
}

struct AdvancedView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("当前位置") {
                    LabeledContent("纬度", value: String(format: "%.6f", model.selection.wgs84Latitude))
                    LabeledContent("经度", value: String(format: "%.6f", model.selection.wgs84Longitude))
                    LabeledContent("海拔", value: String(format: "%.1f", model.selection.altitude))
                    Button("手动设置") { showEditor = true }
                }

                Section("设备") {
                    LabeledContent("连接状态", value: bluetooth.canSendLocation ? "已连接" : bluetooth.state.title)
                    if bluetooth.connectedIdentifier != nil {
                        Button("断开连接", role: .destructive) { bluetooth.disconnect() }
                        if !bluetooth.canSendLocation {
                            Button("重新认证") { bluetooth.retryAuthentication() }
                        }
                    }
                }

                Section("设置") {
                    Button {
                        if let url = URL(string: "shortcuts://") {
                            openURL(url)
                        }
                    } label: {
                        Label("快捷指令", systemImage: "wand.and.stars")
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("权限与关于", systemImage: "gearshape")
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
