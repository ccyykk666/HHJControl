import SwiftUI
import UIKit

struct DeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: HHJBluetoothController

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(bluetooth.state.title, systemImage: bluetooth.canSendLocation ? "checkmark.seal.fill" : "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(bluetooth.canSendLocation ? .green : .primary)

                    if bluetooth.connectedIdentifier != nil {
                        HStack {
                            Button("断开", role: .destructive) { bluetooth.disconnect() }
                            if !bluetooth.canSendLocation {
                                Button("重新认证") { bluetooth.retryAuthentication() }
                            }
                        }
                    }
                }

                Section("设备列表") {
                    if bluetooth.devices.isEmpty {
                        HStack {
                            ProgressView().opacity(bluetooth.state == .scanning ? 1 : 0)
                            Text(bluetooth.state == .scanning ? "正在查找设备…" : "暂未发现设备")
                                .foregroundStyle(.secondary)
                        }
                    } else {
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
                            }
                        }
                    }

                    if bluetooth.state != .scanning && !bluetooth.canSendLocation {
                        Button("重新扫描") { bluetooth.startScanning() }
                    }
                }
            }
            .navigationTitle("选择设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: beginScanningIfNeeded)
            .onChange(of: bluetooth.state) { _, state in
                if state == .ready { dismiss() }
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
}

struct AdvancedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @State private var showEditor = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            Form {
                Section("手动定位") {
                    LabeledContent("纬度", value: String(format: "%.6f", model.selection.mapLatitude))
                    LabeledContent("经度", value: String(format: "%.6f", model.selection.mapLongitude))
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

                Section("诊断与设置") {
                    Button { showLogs = true } label: {
                        Label("通信日志（\(bluetooth.logs.count)）", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        UIPasteboard.general.string = bluetooth.copyableDiagnostics()
                    } label: {
                        Label("复制诊断日志", systemImage: "doc.on.doc")
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
                CoordinateEditorView(selection: $model.selection) {
                    model.mapRequestID = UUID()
                    model.selectedTab = .location
                }
            }
            .sheet(isPresented: $showLogs) { DiagnosticLogView() }
        }
    }
}

private struct DiagnosticLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: HHJBluetoothController

    var body: some View {
        NavigationStack {
            List(bluetooth.logs) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.level.rawValue).font(.caption.weight(.semibold))
                        Spacer()
                        Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(entry.message).font(.caption.monospaced())
                }
            }
            .navigationTitle("通信日志")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
