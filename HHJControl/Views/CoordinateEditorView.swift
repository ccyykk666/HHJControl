import SwiftUI

struct CoordinateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: LocationSelection
    var onSave: () -> Void
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var altitude = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("地图坐标") {
                    TextField("纬度 -90...90", text: $latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("coordinate.latitude")
                    TextField("经度 -180...180", text: $longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("coordinate.longitude")
                    TextField("海拔 -500...9000 米", text: $altitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("coordinate.altitude")
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section { Text("中国范围内的地图坐标会按原协议方向转换为 WGS‑84；境外坐标原样发送。") }
            }
            .navigationTitle("坐标与海拔")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                latitude = String(format: "%.6f", selection.mapLatitude)
                longitude = String(format: "%.6f", selection.mapLongitude)
                altitude = String(format: "%.1f", selection.altitude)
            }
        }
    }

    private func save() {
        guard let lat = Double(latitude), (-90...90).contains(lat), let lon = Double(longitude), (-180...180).contains(lon) else { error = "请输入有效经纬度"; return }
        guard let alt = Double(altitude), (-500...9000).contains(alt) else { error = "海拔必须在 -500 到 9000 米之间"; return }
        selection = LocationSelection(mapCoordinate: .init(latitude: lat, longitude: lon), altitude: alt, address: "手动坐标", source: .manual)
        onSave(); dismiss()
    }
}
