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
    @State private var favoriteAnimationTrigger = 0
    @State private var showConnectionNotice = false
    @State private var connectionNoticeTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                HHJMapView(selection: $model.selection, mapRequestID: model.mapRequestID) { coordinate, source, reverseGeocodingDelay in
                    model.select(
                        coordinate,
                        source: source,
                        moveMap: false,
                        reverseGeocodingDelay: reverseGeocodingDelay
                    )
                } onRegionChange: { region in
                    model.updateSearchRegion(region)
                } onUserLocationUpdate: { location in
                    model.observeMapUserLocation(location)
                }
                .ignoresSafeArea()

                MapTopBlurView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack {
                    if showConnectionNotice {
                        Label("设备已连接", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .allowsHitTesting(false)

                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Spacer()

                    HStack {
                        Spacer()
                        VStack(spacing: 0) {
                            Button { showDevices = true } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(bluetooth.canSendLocation ? .green : .primary)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)

                            Divider().padding(.horizontal, 10)

                            Button {
                                model.useCurrentLocation()
                            } label: {
                                Image(systemName: "location.fill").frame(width: 24, height: 24)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                        }
                        .fixedSize()
                        .glassEffect(.regular, in: .capsule)
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
                            Button {
                                store.toggleFavorite(model.selection)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                favoriteAnimationTrigger += 1
                            } label: {
                                Image(systemName: store.isFavorite(model.selection) ? "star.fill" : "star")
                                    .font(.title3)
                                    .symbolEffect(.bounce, value: favoriteAnimationTrigger)
                                    .foregroundStyle(store.isFavorite(model.selection) ? .orange : .primary)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
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
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(!bluetooth.canSendLocation || !model.selection.isValid)
                        .animation(.easeInOut(duration: 0.2), value: sendButtonState)
                    }
                    .padding(18)
                    .glassEffect(
                        .regular,
                        in: ConcentricRectangle(
                            topLeadingCorner: .concentric(minimum: 28),
                            topTrailingCorner: .concentric(minimum: 28),
                            bottomLeadingCorner: .concentric(minimum: 28),
                            bottomTrailingCorner: .concentric(minimum: 28)
                        )
                    )
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDevices) { DeviceView() }
            .onChange(of: bluetooth.state) { _, state in
                guard state == .ready, !showDevices else { return }
                showConnectedNotice()
            }
            .onDisappear {
                connectionNoticeTask?.cancel()
            }
        }
    }

    private func showConnectedNotice() {
        connectionNoticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            showConnectionNotice = true
        }
        connectionNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                showConnectionNotice = false
            }
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
            UIColor.black.withAlphaComponent(0.8).cgColor,
            UIColor.clear.cgColor
        ]
        fadeMask.locations = [0, 0.6, 1]
        blurView.layer.mask = fadeMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let statusBarHeight = window?.safeAreaInsets.top ?? safeAreaInsets.top
        blurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: statusBarHeight + 20)
        fadeMask.frame = blurView.bounds
        blurView.layer.mask = fadeMask
    }
}
