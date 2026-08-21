import SwiftUI
import UIKit

struct DeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("选择设备").font(.headline)
                HStack {
                    Spacer()
                    Button("完成") { dismiss() }
                        .buttonStyle(.glass)
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
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))

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
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                }
            }
            .padding(20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(uiColor: .systemGroupedBackground))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if abs(contentHeight - height) > 1 { contentHeight = height }
        }
        .presentationDetents([.height(min(max(contentHeight, 220), 650))])
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
                    model.refreshSelectionDetails()
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
