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
                                Image(systemName: "bluetooth")
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
                                Text(model.administrativeArea)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button { store.toggleFavorite(model.selection) } label: {
                                Image(systemName: store.isFavorite(model.selection) ? "star.fill" : "star")
                                    .foregroundStyle(store.isFavorite(model.selection) ? .orange : .primary)
                            }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("location.favorite")
                                .accessibilityLabel(store.isFavorite(model.selection) ? "取消收藏" : "收藏")
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
