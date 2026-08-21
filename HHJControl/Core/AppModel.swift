import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case location, favorites, advanced, search }

    @Published var selectedTab: Tab = .location
    @Published var selection = LocationSelection(mapCoordinate: .init(latitude: 23.1291, longitude: 113.2644), address: "拖动地图或搜索地点")
    @Published var administrativeArea = "正在获取区域…"
    @Published var mapRequestID = UUID()
    @Published var notice: String?
    @Published private(set) var geocodingLogs: [CommunicationLog] = []

    let bluetooth: HHJBluetoothController
    let store: AppDataStore
    let locationProvider: DeviceLocationProvider
    private var geocoder: CLGeocoder?
    private var reverseGeocodingTask: Task<Void, Never>?
    private var reverseGeocodingID = UUID()
    private var didPrepareForLaunch = false

    var diagnosticLogs: [CommunicationLog] {
        (bluetooth.logs + geocodingLogs).sorted { $0.date > $1.date }
    }

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

    func copyableDiagnostics() -> String {
        diagnosticLogs
            .sorted { $0.date < $1.date }
            .map { "[\($0.date.formatted(date: .numeric, time: .standard))] \($0.level.rawValue) \($0.message)" }
            .joined(separator: "\n")
    }

    private func resolveAddress(for coordinate: CLLocationCoordinate2D, updateName: Bool) {
        reverseGeocodingTask?.cancel()
        geocoder?.cancelGeocode()
        let requestID = UUID()
        reverseGeocodingID = requestID
        logGeocoding(.info, "反向地理编码排队：\(coordinateText(coordinate))")

        reverseGeocodingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled,
                  let self,
                  self.isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate) else { return }
            await self.resolveAddressWithCoreLocation(for: coordinate, updateName: updateName, requestID: requestID)
        }
    }

    private func resolveAddressWithCoreLocation(
        for coordinate: CLLocationCoordinate2D,
        updateName: Bool,
        requestID: UUID
    ) async {
        guard !Task.isCancelled,
              isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate) else { return }

        let geocoder = CLGeocoder()
        self.geocoder = geocoder
        logGeocoding(.info, "系统地址服务开始：\(coordinateText(coordinate))")

        let placemark: CLPlacemark?
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            placemark = placemarks.first
            logGeocoding(.info, "系统地址服务返回 \(placemarks.count) 个地点")
        } catch {
            guard !Task.isCancelled,
                  isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate) else { return }
            let error = error as NSError
            if updateName { selection.address = "已选择的位置" }
            administrativeArea = "区域信息不可用"
            logGeocoding(.error, "系统地址服务失败：\(error.domain) (\(error.code)) \(error.localizedDescription)")
            return
        }

        guard !Task.isCancelled,
              isCurrentReverseGeocodingRequest(requestID, coordinate: coordinate),
              let placemark else {
            return
        }

        if updateName {
            selection.address = placemark.name?.nilIfEmpty
                ?? placemark.locality?.nilIfEmpty
                ?? placemark.administrativeArea?.nilIfEmpty
                ?? "已选择的位置"
        }
        if let area = administrativeArea(for: placemark) {
            administrativeArea = area
            logGeocoding(.success, "系统区域信息：\(area)")
        } else {
            administrativeArea = "区域信息不可用"
            logGeocoding(.warning, "系统地址服务未提供可显示的区域信息")
        }
    }

    private func isCurrentReverseGeocodingRequest(_ requestID: UUID, coordinate: CLLocationCoordinate2D) -> Bool {
        reverseGeocodingID == requestID
            && selection.mapCoordinate.latitude == coordinate.latitude
            && selection.mapCoordinate.longitude == coordinate.longitude
    }

    private func logGeocoding(_ level: CommunicationLog.Level, _ message: String) {
        geocodingLogs.append(.init(level: level, message: "地图：\(message)"))
        if geocodingLogs.count > 100 { geocodingLogs.removeFirst(geocodingLogs.count - 100) }
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private func administrativeArea(for placemark: CLPlacemark) -> String? {
        let isChina = placemark.isoCountryCode?.uppercased() == "CN"
        let parts: [String?]

        if isChina {
            parts = [
                placemark.administrativeArea,
                placemark.subAdministrativeArea,
                placemark.locality,
                placemark.subLocality
            ]
        } else {
            parts = [
                placemark.country,
                placemark.administrativeArea,
                placemark.subAdministrativeArea,
                placemark.locality,
                placemark.subLocality
            ]
        }

        return parts
            .compactMap { $0?.nilIfEmpty }
            .uniqued()
            .joined(separator: " ")
            .nilIfEmpty
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
