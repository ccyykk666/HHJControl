import CoreLocation
import XCTest
@testable import HHJControl

final class HHJPacketEncoderTests: XCTestCase {
    func testAuthenticationPayloadUsesUnixSecondsAndVerifiedSuffix() {
        let date = Date(timeIntervalSince1970: 1_777_777_777)
        XCTAssertEqual(String(data: HHJPacketEncoder.authPayload(at: date), encoding: .utf8), "1777777777_dsfds123")
    }

    func testDegreeMinuteFormattingMatchesLegacyQuirk() {
        XCTAssertEqual(HHJPacketEncoder.degreeMinutes(1.5), "130.000000")
        XCTAssertEqual(HHJPacketEncoder.degreeMinutes(-12.3456), "1220.736000")
        XCTAssertEqual(HHJPacketEncoder.degreeMinutes(123.4567), "12327.402000")
        XCTAssertEqual(HHJPacketEncoder.degreeMinutes(0.01), "000.600000")
    }

    func testAltitudeBoundsAndSnapshot() throws {
        let oldTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        defer { NSTimeZone.default = oldTimeZone }
        let date = ISO8601DateFormatter().date(from: "2026-08-21T04:34:56Z")!
        var selection = LocationSelection(mapCoordinate: .init(latitude: -12.3456, longitude: 123.4567), altitude: 69.8, address: "snapshot", source: .manual)
        let payload = try HHJPacketEncoder.locationPayload(selection: selection, date: date)
        XCTAssertEqual(String(data: payload, encoding: .utf8), "$GPGGA,123456.0,1220.736000,S,12327.402000,E,1,,09,0.6,69.8,M,-27.0,M,,$GPRMC,123456.0,A,1220.736000,S,12327.402000,E,0.0,26.1,210826,0.0,E,A")

        selection.altitude = -500
        XCTAssertNoThrow(try HHJPacketEncoder.locationPayload(selection: selection, date: date))
        selection.altitude = 9000
        XCTAssertNoThrow(try HHJPacketEncoder.locationPayload(selection: selection, date: date))
        selection.altitude = 9000.1
        XCTAssertThrowsError(try HHJPacketEncoder.locationPayload(selection: selection, date: date)) { XCTAssertEqual($0 as? HHJPacketError, .invalidAltitude) }
    }
}
