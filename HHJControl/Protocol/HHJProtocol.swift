import CoreLocation
import Foundation

enum HHJProtocolConstants {
    static let authService = "0000FAA1-0000-1000-8000-00805F8C12AB"
    static let authWrite = "000021E1-0000-1000-8000-00805F8A12FB"
    static let authNotify = "000021E2-0000-1000-8000-00805F8A12FB"
    static let dataService = "0000FBB2-0000-1000-8000-00805F8C12AB"
    static let locationWrite = "000032E1-0000-1000-8000-00805F8A12FB"
    static let authSuffix = "_dsfds123"
    static let authSuccess = "authSuc"
}

enum HHJPacketError: LocalizedError, Equatable {
    case invalidCoordinate
    case invalidAltitude

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate: "经纬度超出有效范围"
        case .invalidAltitude: "海拔必须在 -500 到 9000 米之间"
        }
    }
}

enum HHJPacketEncoder {
    static func authPayload(at date: Date) -> Data {
        Data("\(Int(date.timeIntervalSince1970))\(HHJProtocolConstants.authSuffix)".utf8)
    }

    static func locationPayload(selection: LocationSelection, date: Date) throws -> Data {
        guard (-90...90).contains(selection.wgs84Latitude), (-180...180).contains(selection.wgs84Longitude) else {
            throw HHJPacketError.invalidCoordinate
        }
        guard (-500...9000).contains(selection.altitude) else { throw HHJPacketError.invalidAltitude }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HHmmss"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "ddMMyy"

        let time = timeFormatter.string(from: date) + ".0"
        let day = dateFormatter.string(from: date)
        let latitude = degreeMinutes(selection.wgs84Latitude)
        let longitude = degreeMinutes(selection.wgs84Longitude)
        let northSouth = selection.wgs84Latitude >= 0 ? "N" : "S"
        let eastWest = selection.wgs84Longitude >= 0 ? "E" : "W"
        let altitude = String(format: "%.1f", selection.altitude)

        let gga = "$GPGGA,\(time),\(latitude),\(northSouth),\(longitude),\(eastWest),1,,09,0.6,\(altitude),M,-27.0,M,,"
        let rmc = "$GPRMC,\(time),A,\(latitude),\(northSouth),\(longitude),\(eastWest),0.0,26.1,\(day),0.0,E,A"
        return Data((gga + rmc).utf8)
    }

    static func degreeMinutes(_ value: Double) -> String {
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutes = (absolute - Double(degrees)) * 60
        var encoded = String(format: "%02d%09.6f", degrees, minutes)
        if encoded.hasPrefix("0") { encoded.removeFirst() }
        return encoded
    }
}

enum CoordinateConverter {
    static func isInChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (72.004...137.8347).contains(coordinate.longitude) && (0.8293...55.8271).contains(coordinate.latitude)
    }

    static func gcj02ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        let delta = transform(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return .init(latitude: coordinate.latitude - delta.latitude, longitude: coordinate.longitude - delta.longitude)
    }

    private static func transform(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        let a = 6_378_245.0
        let eccentricity = 0.00669342162296594323
        let x = longitude - 105.0
        let y = latitude - 35.0
        var latitudeDelta = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        latitudeDelta += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        latitudeDelta += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        latitudeDelta += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        var longitudeDelta = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        longitudeDelta += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        longitudeDelta += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        longitudeDelta += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        let radians = latitude / 180 * .pi
        var magic = sin(radians)
        magic = 1 - eccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        latitudeDelta = latitudeDelta * 180 / ((a * (1 - eccentricity)) / (magic * sqrtMagic) * .pi)
        longitudeDelta = longitudeDelta * 180 / (a / sqrtMagic * cos(radians) * .pi)
        return .init(latitude: latitudeDelta, longitude: longitudeDelta)
    }
}

