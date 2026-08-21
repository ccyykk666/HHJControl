import CoreLocation
import SwiftUI

struct CoordinateEditorView: View {
    private enum Field: Hashable {
        case latitude, longitude, altitude
    }

    @Environment(\.dismiss) private var dismiss
    @Binding var selection: LocationSelection
    var mapCoordinateReference: MapCoordinateReference
    var onSave: () -> Void
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var altitude = ""
    @State private var error: String?
    @FocusState private var editingField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("地图坐标") {
                    coordinateField(
                        title: "纬度",
                        text: $latitude,
                        value: latitudeValue,
                        range: -90...90,
                        step: 1,
                        field: .latitude,
                        format: "%.6f"
                    )
                    coordinateField(
                        title: "经度",
                        text: $longitude,
                        value: longitudeValue,
                        range: -180...180,
                        step: 1,
                        field: .longitude,
                        format: "%.6f"
                    )
                    coordinateField(
                        title: "海拔",
                        text: $altitude,
                        value: altitudeValue,
                        range: -500...9000,
                        step: 1,
                        field: .altitude,
                        format: "%.1f"
                    )
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("经纬度与海拔")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                }
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
        field: Field,
        format: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            if editingField == field {
                TextField("", text: text)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .focused($editingField, equals: field)
                    .frame(minWidth: 92)
            } else {
                Button {
                    editingField = field
                } label: {
                    Text(String(format: format, value.wrappedValue))
                        .contentTransition(.numericText(value: value.wrappedValue))
                        .frame(minWidth: 92, alignment: .trailing)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            Stepper("", value: animatedValue(value), in: range, step: step)
                .labelsHidden()
        }
    }

    private func animatedValue(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                editingField = nil
                withAnimation(.snappy) { value.wrappedValue = newValue }
            }
        )
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
