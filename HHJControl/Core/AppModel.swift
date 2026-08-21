import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case location, favorites, advanced, search }

    @Published var selectedTab: Tab = .location
    @Published var selection = LocationSelection(mapCoordinate: .init(latitude: 23.1291, longitude: 113.2644), address: "拖动地图或搜索地点")
    @Published var mapRequestID = UUID()
    @Published var notice: String?

    let bluetooth: HHJBluetoothController
    let store: AppDataStore
    let locationProvider: DeviceLocationProvider
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var didPrepareForLaunch = false

    init(bluetooth: HHJBluetoothController? = nil, store: AppDataStore? = nil) {
        self.bluetooth = bluetooth ?? HHJBluetoothController()
        self.store = store ?? AppDataStore()
        self.locationProvider = DeviceLocationProvider()
    }

    func prepareForLaunch() {
        if !didPrepareForLaunch {
            didPrepareForLaunch = true
            bluetooth.requestAuthorization()
        }
        useCurrentLocation(reportFailure: false)
    }

    func select(_ coordinate: CLLocationCoordinate2D, address: String? = nil, altitude: Double? = nil, source: LocationSelection.Source) {
        selection = LocationSelection(mapCoordinate: coordinate, altitude: altitude ?? selection.altitude, address: address ?? "正在获取地址…", source: source)
        mapRequestID = UUID()
        if address == nil { resolveAddress(for: coordinate) }
    }

    func load(_ value: LocationSelection) {
        selection = value
        selectedTab = .location
        mapRequestID = UUID()
    }

    func useCurrentLocation(reportFailure: Bool = true) {
        locationProvider.requestLocation { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let location):
                self.select(location.coordinate, altitude: location.altitude.isFinite ? location.altitude : self.selection.altitude, source: .currentLocation)
            case .failure(let error):
                if reportFailure { self.notice = error.localizedDescription }
            }
        }
    }

    func sendSelection() {
        do {
            guard selection.isValid else { throw HHJPacketError.invalidAltitude }
            try bluetooth.sendLocation(selection)
            store.addRecord(.init(selection: selection, result: .success, message: "已写入设备"))
            notice = "定位数据已发送"
        } catch {
            store.addRecord(.init(selection: selection, result: .failure, message: error.localizedDescription))
            notice = error.localizedDescription
        }
    }

    private func resolveAddress(for coordinate: CLLocationCoordinate2D) {
        reverseGeocodingRequest?.cancel()
        guard let request = MKReverseGeocodingRequest(location: .init(latitude: coordinate.latitude, longitude: coordinate.longitude)) else {
            selection.address = "已选择的位置"
            return
        }
        reverseGeocodingRequest = request
        Task { [weak self] in
            let items = try? await request.mapItems
            let item = items?.first
            guard let self,
                  self.selection.mapCoordinate.latitude == coordinate.latitude,
                  self.selection.mapCoordinate.longitude == coordinate.longitude else { return }
            self.selection.address = item?.name?.nilIfEmpty ?? "已选择的位置"
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
