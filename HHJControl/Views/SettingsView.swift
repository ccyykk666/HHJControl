import CoreBluetooth
import CoreLocation
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("权限") {
                LabeledContent("蓝牙", value: bluetoothStatus)
                LabeledContent("使用期间定位", value: locationStatus)
                Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            Section("隐私") {
                Label("不跟踪、不上传、不使用统计 SDK", systemImage: "hand.raised.fill")
                Text("收藏、最近记录和偏好仅保存在本机。App 不读取或保存证书、GitHub Token 和签名材料。")
            }
            Section("关于") {
                LabeledContent("应用", value: "HHJControl")
                LabeledContent("版本", value: version)
                LabeledContent("最低系统", value: "iOS 26.0")
                Text("HHJControl 只负责通过 BLE 配置兼容尾插，本身不能通过公开 iOS API 修改系统定位。")
            }
        }.navigationTitle("设置")
    }

    private var bluetoothStatus: String {
        switch CBManager.authorization {
        case .allowedAlways: "已允许"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        case .notDetermined: "尚未请求"
        @unknown default: "未知"
        }
    }
    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "已允许"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        case .notDetermined: "尚未请求"
        @unknown default: "未知"
        }
    }
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }
}

