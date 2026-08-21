import CoreLocation
import SwiftUI

struct CoordinateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: LocationSelection
    var mapCoordinateReference: MapCoordinateReference
    var onSave: () -> Void
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var altitude = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("地图坐标") {
                    coordinateField(
                        title: "纬度 (°)",
                        text: $latitude,
                        value: latitudeValue,
                        range: -90...90,
                        step: 0.0001,
                        identifier: "coordinate.latitude"
                    )
                    coordinateField(
                        title: "经度 (°)",
                        text: $longitude,
                        value: longitudeValue,
                        range: -180...180,
                        step: 0.0001,
                        identifier: "coordinate.longitude"
                    )
                    coordinateField(
                        title: "海拔 (m)",
                        text: $altitude,
                        value: altitudeValue,
                        range: -500...9000,
                        step: 1,
                        identifier: "coordinate.altitude"
                    )
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("坐标与海拔")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                latitude = String(format: "%.6f", selection.wgs84Latitude)
                longitude = String(format: "%.6f", selection.wgs84Longitude)
                altitude = String(format: "%.1f", selection.altitude)
            }
        }
    }

    private func coordinateField(
        title: String,
        text: Binding<String>,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        identifier: String
    ) -> some View {
        HStack {
            Text(title)
            TextField("", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel("调整\(title)")
        }
    }

    private var latitudeValue: Binding<Double> {
        Binding(
            get: { Double(latitude) ?? selection.wgs84Latitude },
            set: { latitude = String(format: "%.6f", $0) }
        )
    }

    private var longitudeValue: Binding<Double> {
        Binding(
            get: { Double(longitude) ?? selection.wgs84Longitude },
            set: { longitude = String(format: "%.6f", $0) }
        )
    }

    private var altitudeValue: Binding<Double> {
        Binding(
            get: { Double(altitude) ?? selection.altitude },
            set: { altitude = String(format: "%.1f", $0) }
        )
    }

    private func save() {
        guard let lat = Double(latitude), (-90...90).contains(lat), let lon = Double(longitude), (-180...180).contains(lon) else { error = "请输入有效经纬度"; return }
        guard let alt = Double(altitude), (-500...9000).contains(alt) else { error = "海拔必须在 -500 到 9000 米之间"; return }
        let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        selection = LocationSelection(
            mapCoordinate: mapCoordinateReference.displayCoordinate(forWGS84: wgs84),
            wgs84Coordinate: wgs84,
            altitude: alt,
            address: "手动坐标",
            source: .manual
        )
        onSave(); dismiss()
    }
}
