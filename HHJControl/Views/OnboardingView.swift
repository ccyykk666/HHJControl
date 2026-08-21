import SwiftUI

struct OnboardingView: View {
    var complete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.viewfinder").font(.system(size: 64, weight: .medium)).foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("欢迎使用").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("选择地点并为iPhone模拟位置数据").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                OnboardingRow(icon: "cable.connector", title: "连接HHJ尾插", detail: "连接兼容设备以修改系统定位。")
                OnboardingRow(icon: "map", title: "选择地点", detail: "在地图中拖动或搜索选点。")
                OnboardingRow(icon: "antenna.radiowaves.left.and.right", title: "授权必要权限", detail: "只请求蓝牙和使用期间定位权限。")
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
