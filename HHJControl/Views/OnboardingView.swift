import SwiftUI

struct OnboardingView: View {
    var complete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.viewfinder").font(.system(size: 64, weight: .medium)).foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("欢迎使用").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("选择地点，经由兼容设备为 iPhone 提供模拟 GPS 数据。").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                OnboardingRow(icon: "cable.connector", title: "需要兼容设备", detail: "App 无法脱离硬件独立修改系统定位。")
                OnboardingRow(icon: "antenna.radiowaves.left.and.right", title: "仅使用必要权限", detail: "只请求蓝牙和使用期间定位权限。")
                OnboardingRow(icon: "lock.shield", title: "数据留在本机", detail: "没有账号、统计 SDK 或网络上传。")
            }
            Spacer()
            Button("开始使用", action: complete).buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }
        .padding(28)
        .interactiveDismissDisabled()
    }
}

private struct OnboardingRow: View {
    var icon: String; var title: String; var detail: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
