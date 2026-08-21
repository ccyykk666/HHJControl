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
                LabeledContent("应用", value: "HHJControl")
                LabeledContent("版本", value: version)
                Link("国外地址来源:Geoapify", destination: URL(string: "https://www.geoapify.com/")!)
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
