import CoreLocation
import Foundation

struct GeoapifyPlace {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let administrativeArea: String
    let countryCode: String?
}

enum GeoapifyError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case noResults

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "海外搜索服务尚未配置"
        case .invalidResponse: "海外搜索服务暂时不可用"
        case .noResults: "未找到相关地点"
        }
    }
}

struct GeoapifyService: Sendable {
    private let apiKey: String?

    init(bundle: Bundle = .main) {
        let value = bundle.object(forInfoDictionaryKey: "GEOAPIFY_API_KEY") as? String
        apiKey = value?.trimmingCharacters(in: .whitespacesAndNewlines).usableBuildSetting
    }

    func search(_ text: String, bias: CLLocationCoordinate2D?) async throws -> [GeoapifyPlace] {
        var items = baseQueryItems()
        items.append(.init(name: "text", value: text))
        items.append(.init(name: "format", value: "json"))
        items.append(.init(name: "limit", value: "20"))
        items.append(.init(name: "lang", value: preferredLanguage))
        if let bias {
            items.append(.init(name: "bias", value: "proximity:\(bias.longitude),\(bias.latitude)"))
        }

        return try await request(path: "/v1/geocode/autocomplete", queryItems: items)
            .filter { $0.countryCode?.lowercased() != "cn" }
            .prefix(10)
            .map { $0 }
    }

    func reverse(_ coordinate: CLLocationCoordinate2D) async throws -> GeoapifyPlace {
        var items = baseQueryItems()
        items.append(.init(name: "lat", value: String(coordinate.latitude)))
        items.append(.init(name: "lon", value: String(coordinate.longitude)))
        items.append(.init(name: "format", value: "json"))
        items.append(.init(name: "lang", value: preferredLanguage))
        guard let place = try await request(path: "/v1/geocode/reverse", queryItems: items).first else {
            throw GeoapifyError.noResults
        }
        return place
    }

    private func baseQueryItems() -> [URLQueryItem] {
        [.init(name: "apiKey", value: apiKey)]
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> [GeoapifyPlace] {
        guard apiKey != nil else { throw GeoapifyError.missingAPIKey }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.geoapify.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else { throw GeoapifyError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeoapifyError.invalidResponse
        }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        return payload.results.map(\.place)
    }

    private var preferredLanguage: String {
        Locale.preferredLanguages.first?
            .split(separator: "-")
            .first
            .map(String.init) ?? "zh"
    }
}

private extension GeoapifyService {
    struct Response: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let placeID: String?
        let name: String?
        let addressLine1: String?
        let addressLine2: String?
        let formatted: String?
        let country: String?
        let countryCode: String?
        let state: String?
        let county: String?
        let city: String?
        let suburb: String?
        let district: String?
        let lat: Double
        let lon: Double

        enum CodingKeys: String, CodingKey {
            case placeID = "place_id"
            case name
            case addressLine1 = "address_line1"
            case addressLine2 = "address_line2"
            case formatted, country
            case countryCode = "country_code"
            case state, county, city, suburb, district, lat, lon
        }

        var place: GeoapifyPlace {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let area = [country, state, county, city, district, suburb]
                .compactMap(\.nonempty)
                .uniqued()
                .joined(separator: " ")
            return GeoapifyPlace(
                id: placeID ?? "\(lat),\(lon)",
                coordinate: coordinate,
                title: addressLine1?.nonempty ?? name?.nonempty ?? city?.nonempty ?? "已选择的位置",
                subtitle: formatted?.nonempty ?? addressLine2?.nonempty ?? area,
                administrativeArea: area,
                countryCode: countryCode
            )
        }
    }
}

private extension Optional where Wrapped == String {
    var nonempty: String? {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nonempty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var usableBuildSetting: String? {
        guard !isEmpty, !hasPrefix("$(") else { return nil }
        return self
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
