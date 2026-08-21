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
            Section("关于") {
                LabeledContent("应用", value: "设备控制")
                LabeledContent("版本", value: version)
                LabeledContent("最低系统", value: "iOS 26.0")
                Link("海外地址服务：Geoapify", destination: URL(string: "https://www.geoapify.com/")!)
                Text("本应用只负责通过 BLE 配置兼容设备，本身不能通过公开 iOS API 修改系统定位。")
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
