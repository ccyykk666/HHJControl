import SwiftUI

struct LocationView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @EnvironmentObject private var store: AppDataStore
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                HHJMapView(selection: $model.selection, mapRequestID: model.mapRequestID) { coordinate, source in
                    model.select(coordinate, source: source)
                }
                .ignoresSafeArea()

                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Button { model.selectedTab = .device } label: {
                        Label(bluetooth.state.title, systemImage: bluetooth.canSendLocation ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    HStack {
                        Spacer()
                        Button(action: model.useCurrentLocation) { Image(systemName: "location.fill").frame(width: 24, height: 24) }
                            .buttonStyle(.glass)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.selection.address).font(.headline).lineLimit(2)
                                Text(String(format: "地图 %.6f, %.6f", model.selection.mapLatitude, model.selection.mapLongitude))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if CoordinateConverter.isInChina(model.selection.mapCoordinate) {
                                    Text(String(format: "发送 WGS‑84 %.6f, %.6f", model.selection.wgs84Latitude, model.selection.wgs84Longitude))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button { store.addFavorite(model.selection); model.notice = "已加入收藏" } label: { Image(systemName: "star") }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("location.favorite")
                        }
                        HStack {
                            Label(String(format: "%.1f m", model.selection.altitude), systemImage: "mountain.2")
                            Spacer()
                            Button("编辑坐标与海拔") { showEditor = true }.font(.subheadline)
                                .accessibilityIdentifier("location.editor")
                        }
                        Button(action: model.sendSelection) {
                            Label("设置定位", systemImage: "location.circle.fill").frame(maxWidth: .infinity).font(.headline)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("location.send")
                        .disabled(!bluetooth.canSendLocation || !model.selection.isValid)
                        if !bluetooth.canSendLocation {
                            Button("前往设备页连接或重新认证") { model.selectedTab = .device }
                                .font(.footnote).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditor) { CoordinateEditorView(selection: $model.selection) { model.mapRequestID = UUID() } }
        }
    }
}
