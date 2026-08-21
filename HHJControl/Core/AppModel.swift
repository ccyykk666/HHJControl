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
    private(set) var searchRegion = MKCoordinateRegion(
        center: .init(latitude: 23.1291, longitude: 113.2644),
        latitudinalMeters: 50_000,
        longitudinalMeters: 50_000
    )

    let bluetooth: HHJBluetoothController
    let store: AppDataStore
    let locationProvider: DeviceLocationProvider
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var reverseGeocodingTask: Task<Void, Never>?
    private var reverseGeocodingID = UUID()
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

    func select(_ item: MKMapItem, title: String? = nil, regionFallback: String? = nil) {
        reverseGeocodingTask?.cancel()
        reverseGeocodingRequest?.cancel()
        reverseGeocodingID = UUID()

        let coordinate = item.location.coordinate
        selection = LocationSelection(
            mapCoordinate: coordinate,
            altitude: selection.altitude,
            address: title?.nilIfEmpty
                ?? item.name?.nilIfEmpty
                ?? item.address?.shortAddress?.nilIfEmpty
                ?? "已选择的位置",
            source: .search
        )
        let regionCode = item.addressRepresentations?.region?.identifier ?? item.placemark.isoCountryCode
        let fallback = regionCode?.uppercased() == "CN" ? nil : regionFallback?.nilIfEmpty
        administrativeArea = administrativeArea(for: item)
            ?? fallback
            ?? "区域信息不可用"
        mapRequestID = UUID()
    }

    func updateSearchRegion(_ region: MKCoordinateRegion) {
        searchRegion = region
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
        reverseGeocodingTask?.cancel()
        reverseGeocodingRequest?.cancel()
        let requestID = UUID()
        reverseGeocodingID = requestID

        reverseGeocodingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled,
                  let self,
                  self.isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate) else { return }

            guard let request = MKReverseGeocodingRequest(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ) else {
                if updateName { self.selection.address = "已选择的位置" }
                self.administrativeArea = "区域信息不可用"
                return
            }
            self.reverseGeocodingRequest = request

            let item: MKMapItem?
            do {
                let items = try await request.mapItems
                item = items.first
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate) else { return }
                if updateName { self.selection.address = "已选择的位置" }
                self.administrativeArea = "区域信息不可用"
                return
            }

            guard !Task.isCancelled,
                  self.isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate) else { return }
            if updateName {
                self.selection.address = item?.name?.nilIfEmpty
                    ?? item?.address?.shortAddress?.nilIfEmpty
                    ?? item?.addressRepresentations?.cityName?.nilIfEmpty
                    ?? "已选择的位置"
            }
            if let area = item.flatMap(self.administrativeArea(for:)) {
                self.administrativeArea = area
            } else {
                self.administrativeArea = "区域信息不可用"
            }
        }
    }

    private func isCurrentReverseGeocodingRequest(_ requestID: UUID, coordinate: CLLocationCoordinate2D) -> Bool {
        reverseGeocodingID == requestID
            && selection.mapCoordinate.latitude == coordinate.latitude
            && selection.mapCoordinate.longitude == coordinate.longitude
    }

    private func administrativeArea(for item: MKMapItem) -> String? {
        let placemark = item.placemark
        let representations = item.addressRepresentations
        let fullAddress = item.address?.fullAddress.nilIfEmpty
        let regionCode = representations?.region?.identifier ?? placemark.isoCountryCode
        let isChina = regionCode?.uppercased() == "CN"

        if isChina {
            return [
                placemark.administrativeArea,
                placemark.subAdministrativeArea,
                placemark.locality,
                placemark.subLocality,
                representations?.cityName
            ]
            .compactMap { $0?.nilIfEmpty }
            .uniqued()
            .joined(separator: " ")
            .nilIfEmpty
        }

        return representations?.cityWithContext?.nilIfEmpty
            ?? [
                representations?.regionName ?? placemark.country,
                placemark.administrativeArea,
                placemark.subAdministrativeArea,
                representations?.cityName ?? placemark.locality,
                placemark.subLocality
            ]
            .compactMap { $0?.nilIfEmpty }
            .uniqued()
            .joined(separator: " ")
            .nilIfEmpty
            ?? fullAddress
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
