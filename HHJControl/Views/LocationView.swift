import SwiftUI

struct LocationView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @EnvironmentObject private var store: AppDataStore
    @State private var showDevices = false

    var body: some View {
        NavigationStack {
            ZStack {
                HHJMapView(selection: $model.selection, mapRequestID: model.mapRequestID) { coordinate, source in
                    model.select(coordinate, source: source, moveMap: false)
                }
                .ignoresSafeArea()

                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Spacer()

                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Button { showDevices = true } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(bluetooth.canSendLocation ? .green : .primary)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("蓝牙，\(bluetooth.state.title)")

                            Button {
                                model.useCurrentLocation()
                            } label: {
                                Image(systemName: "location.fill").frame(width: 24, height: 24)
                            }
                            .buttonStyle(.glass)
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.selection.address).font(.headline).lineLimit(2)
                                Text(String(format: "经纬度 %.6f, %.6f", model.selection.mapLatitude, model.selection.mapLongitude))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { store.addFavorite(model.selection); model.notice = "已加入收藏" } label: { Image(systemName: "star") }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("location.favorite")
                        }
                        Button(action: model.sendSelection) {
                            Label("设置定位", systemImage: "location.circle.fill").frame(maxWidth: .infinity).font(.headline)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("location.send")
                        .disabled(!bluetooth.canSendLocation || !model.selection.isValid)
                    }
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDevices) { DeviceView() }
        }
    }
}
