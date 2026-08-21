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
        guard (-90...90).contains(selection.mapLatitude), (-180...180).contains(selection.mapLongitude) else {
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
        let latitude = degreeMinutes(selection.mapLatitude)
        let longitude = degreeMinutes(selection.mapLongitude)
        let northSouth = selection.mapLatitude >= 0 ? "N" : "S"
        let eastWest = selection.mapLongitude >= 0 ? "E" : "W"
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

}
