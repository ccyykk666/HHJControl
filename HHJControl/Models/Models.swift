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

    init(
        mapCoordinate: CLLocationCoordinate2D,
        wgs84Coordinate: CLLocationCoordinate2D? = nil,
        altitude: Double = 69.8,
        address: String = "地图选点",
        source: Source = .map
    ) {
        self.mapLatitude = mapCoordinate.latitude
        self.mapLongitude = mapCoordinate.longitude
        self.wgs84Latitude = wgs84Coordinate?.latitude ?? mapCoordinate.latitude
        self.wgs84Longitude = wgs84Coordinate?.longitude ?? mapCoordinate.longitude
        self.altitude = altitude
        self.address = address
        self.source = source
    }

    var mapCoordinate: CLLocationCoordinate2D { .init(latitude: mapLatitude, longitude: mapLongitude) }
    var wgs84Coordinate: CLLocationCoordinate2D { .init(latitude: wgs84Latitude, longitude: wgs84Longitude) }
    var isValid: Bool {
        (-90...90).contains(wgs84Latitude) && (-180...180).contains(wgs84Longitude) && (-500...9000).contains(altitude)
    }

    mutating func updateMapCoordinate(_ coordinate: CLLocationCoordinate2D) {
        mapLatitude = coordinate.latitude
        mapLongitude = coordinate.longitude
    }

    private enum CodingKeys: String, CodingKey {
        case id, mapLatitude, mapLongitude, wgs84Latitude, wgs84Longitude, altitude, address, source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mapLatitude = try values.decode(Double.self, forKey: .mapLatitude)
        mapLongitude = try values.decode(Double.self, forKey: .mapLongitude)
        wgs84Latitude = try values.decodeIfPresent(Double.self, forKey: .wgs84Latitude) ?? mapLatitude
        wgs84Longitude = try values.decodeIfPresent(Double.self, forKey: .wgs84Longitude) ?? mapLongitude
        altitude = try values.decode(Double.self, forKey: .altitude)
        address = try values.decode(String.self, forKey: .address)
        source = try values.decode(Source.self, forKey: .source)
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
