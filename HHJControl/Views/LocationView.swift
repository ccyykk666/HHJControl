import SwiftUI
import UIKit

struct LocationView: View {
    private enum SendButtonState: Equatable {
        case idle, sending, success, failure
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bluetooth: HHJBluetoothController
    @EnvironmentObject private var store: AppDataStore
    @State private var showDevices = false
    @State private var sendButtonState: SendButtonState = .idle
    @State private var sendFeedbackTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                HHJMapView(selection: $model.selection, mapRequestID: model.mapRequestID) { coordinate, source in
                    model.select(coordinate, source: source, moveMap: false)
                } onRegionChange: { region in
                    model.updateSearchRegion(region)
                } onUserLocationUpdate: { location in
                    model.observeMapUserLocation(location)
                }
                .ignoresSafeArea()

                MapTopBlurView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

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
                        Button(action: sendLocation) {
                            HStack(spacing: 8) {
                                switch sendButtonState {
                                case .idle:
                                    Image(systemName: "location.circle.fill")
                                    Text("设置定位")
                                case .sending:
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                    Text("设置中…")
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("已设置")
                                case .failure:
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text("设置失败")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("location.send")
                        .accessibilityLabel(sendButtonTitle)
                        .disabled(!bluetooth.canSendLocation || !model.selection.isValid)
                        .animation(.easeInOut(duration: 0.2), value: sendButtonState)
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

    private var sendButtonTitle: String {
        switch sendButtonState {
        case .idle: "设置定位"
        case .sending: "设置中"
        case .success: "已设置"
        case .failure: "设置失败"
        }
    }

    private func sendLocation() {
        guard sendButtonState == .idle else { return }
        sendFeedbackTask?.cancel()
        sendButtonState = .sending
        let succeeded = model.sendSelection()
        sendFeedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(450))
                sendButtonState = succeeded ? .success : .failure
                try await Task.sleep(for: .seconds(1))
                sendButtonState = .idle
            } catch {
                sendButtonState = .idle
            }
        }
    }
}

private struct MapTopBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> TopBlurContainerView {
        TopBlurContainerView()
    }

    func updateUIView(_ uiView: TopBlurContainerView, context: Context) {
        uiView.setNeedsLayout()
    }
}

private final class TopBlurContainerView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let fadeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        fadeMask.colors = [
            UIColor.black.cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor,
            UIColor.clear.cgColor
        ]
        fadeMask.locations = [0, 0.62, 1]
        blurView.layer.mask = fadeMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let statusBarHeight = window?.safeAreaInsets.top ?? safeAreaInsets.top
        blurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: statusBarHeight + 28)
        fadeMask.frame = blurView.bounds
    }
}
