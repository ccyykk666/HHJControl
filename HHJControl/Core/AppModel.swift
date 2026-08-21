import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case location, favorites, advanced, search }

    @Published var selectedTab: Tab = .location
    @Published var selection = LocationSelection(mapCoordinate: .init(latitude: 23.1291, longitude: 113.2644), address: "拖动地图或搜索地点")
    @Published var administrativeArea = "正在获取区域…"
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
        guard !didPrepareForLaunch else { return }
        didPrepareForLaunch = true
        bluetooth.requestAuthorization()
        useCurrentLocation(reportFailure: false)
    }

    func select(
        _ coordinate: CLLocationCoordinate2D,
        address: String? = nil,
        altitude: Double? = nil,
        source: LocationSelection.Source,
        moveMap: Bool = true
    ) {
        selection = LocationSelection(mapCoordinate: coordinate, altitude: altitude ?? selection.altitude, address: address ?? "正在获取地址…", source: source)
        administrativeArea = "正在获取区域…"
        if moveMap { mapRequestID = UUID() }
        resolveAddress(for: coordinate, updateName: address == nil)
    }

    func load(_ value: LocationSelection) {
        selection = value
        administrativeArea = "正在获取区域…"
        selectedTab = .location
        mapRequestID = UUID()
        resolveAddress(for: value.mapCoordinate, updateName: false)
    }

    func refreshSelectionDetails() {
        administrativeArea = "正在获取区域…"
        resolveAddress(for: selection.mapCoordinate, updateName: false)
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

    private func resolveAddress(for coordinate: CLLocationCoordinate2D, updateName: Bool) {
        reverseGeocodingRequest?.cancel()
        guard let request = MKReverseGeocodingRequest(location: .init(latitude: coordinate.latitude, longitude: coordinate.longitude)) else {
            if updateName { selection.address = "已选择的位置" }
            administrativeArea = "区域信息不可用"
            return
        }
        reverseGeocodingRequest = request
        Task { [weak self] in
            let items = try? await request.mapItems
            let item = items?.first
            guard let self,
                  self.selection.mapCoordinate.latitude == coordinate.latitude,
                  self.selection.mapCoordinate.longitude == coordinate.longitude else { return }
            if updateName { self.selection.address = item?.name?.nilIfEmpty ?? "已选择的位置" }
            self.administrativeArea = [
                item?.placemark.country,
                item?.placemark.administrativeArea,
                item?.placemark.subAdministrativeArea,
                item?.placemark.locality,
                item?.placemark.subLocality
            ]
            .compactMap { $0?.nilIfEmpty }
            .uniqued()
            .joined()
            .nilIfEmpty ?? "区域信息不可用"
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
