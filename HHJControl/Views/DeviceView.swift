import SwiftUI
import UIKit

struct DeviceView: View {
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(bluetooth.state.title, systemImage: bluetooth.canSendLocation ? "checkmark.seal.fill" : "antenna.radiowaves.left.and.right")
                            .font(.title3.weight(.semibold)).foregroundStyle(bluetooth.canSendLocation ? .green : .primary)
                        Text(stateDetail).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            if bluetooth.connectedIdentifier != nil {
                                Button("断开", role: .destructive) { bluetooth.disconnect() }
                                if !bluetooth.canSendLocation { Button("重新认证") { bluetooth.retryAuthentication() } }
                            } else {
                                Button(bluetooth.state == .scanning ? "停止扫描" : "扫描设备") {
                                    if bluetooth.state == .scanning { bluetooth.stopScanning() } else { bluetooth.startScanning() }
                                }
                            }
                        }.buttonStyle(.bordered)
                    }.padding(.vertical, 6)
                } header: { Text("连接") }

                if bluetooth.state == .scanning || !bluetooth.devices.isEmpty {
                    Section("附近 BLE 外设") {
                        ForEach(bluetooth.devices) { device in
                            Button { bluetooth.connect(to: device.id) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(device.name).foregroundStyle(.primary)
                                        Text(device.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(); Text("\(device.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("协议阶段") {
                    LabeledContent("当前阶段", value: bluetooth.state.title)
                    LabeledContent("认证服务", value: "FAA1")
                    LabeledContent("数据服务", value: "FBB2")
                    LabeledContent("定位特征", value: "32E1")
                }

                Section("诊断") {
                    Button { showLogs = true } label: { Label("通信日志（\(bluetooth.logs.count)）", systemImage: "doc.text.magnifyingglass") }
                    Button {
                        UIPasteboard.general.string = bluetooth.copyableDiagnostics()
                    } label: { Label("复制诊断日志", systemImage: "doc.on.doc") }
                }

                Section { NavigationLink { SettingsView() } label: { Label("权限、隐私与关于", systemImage: "gearshape") } }
            }
            .navigationTitle("设备")
            .sheet(isPresented: $showLogs) { DiagnosticLogView() }
        }
    }

    private var stateDetail: String {
        switch bluetooth.state {
        case .ready: "设备服务、定位特征和认证均已通过，可以发送位置。"
        case .failed(let message), .bluetoothUnavailable(let message): message
        default: "仅兼容具有已验证 HHJ 服务 UUID 的尾插；扫描不按名称过滤。"
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
                    HStack { Text(entry.level.rawValue).font(.caption.weight(.semibold)); Spacer(); Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Text(entry.message).font(.caption.monospaced())
                }
            }
            .navigationTitle("通信日志")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

