import CoreLocation
import Foundation

struct LocationSelection: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case map, longPress, search, currentLocation, favorite, recent, manual }

    var id = UUID()
    var mapLatitude: Double
    var mapLongitude: Double
    var wgs84Latitude: Double
    var wgs84Longitude: Double
    var altitude: Double
    var address: String
    var source: Source

    init(mapCoordinate: CLLocationCoordinate2D, altitude: Double = 69.8, address: String = "地图选点", source: Source = .map) {
        let converted = CoordinateConverter.gcj02ToWGS84(mapCoordinate)
        self.mapLatitude = mapCoordinate.latitude
        self.mapLongitude = mapCoordinate.longitude
        self.wgs84Latitude = converted.latitude
        self.wgs84Longitude = converted.longitude
        self.altitude = altitude
        self.address = address
        self.source = source
    }

    var mapCoordinate: CLLocationCoordinate2D { .init(latitude: mapLatitude, longitude: mapLongitude) }
    var wgs84Coordinate: CLLocationCoordinate2D { .init(latitude: wgs84Latitude, longitude: wgs84Longitude) }
    var isValid: Bool {
        (-90...90).contains(mapLatitude) && (-180...180).contains(mapLongitude) && (-500...9000).contains(altitude)
    }
}

struct SavedPlace: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var selection: LocationSelection
    var createdAt = Date()
}

struct LocationRecord: Codable, Identifiable, Equatable, Sendable {
    enum Result: String, Codable, Sendable { case success, failure }
    var id = UUID()
    var selection: LocationSelection
    var result: Result
    var message: String
    var createdAt = Date()
}

struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var rssi: Int
    var isConnected: Bool
}

struct CommunicationLog: Identifiable, Equatable, Sendable {
    enum Level: String, Sendable { case info = "信息", success = "成功", warning = "警告", error = "错误" }
    var id = UUID()
    var date = Date()
    var level: Level
    var message: String
}

