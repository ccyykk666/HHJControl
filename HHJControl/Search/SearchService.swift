import MapKit
import SwiftUI

struct SearchResolvedPlace: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    let title: String
    let subtitle: String
}

enum SearchRegionMode: String, CaseIterable, Identifiable {
    case domestic = "国内"
    case international = "国外"

    var id: Self { self }
}

@MainActor
final class SearchService: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            results = []
            errorMessage = nil
            completer.queryFragment = acceptsCompletions ? query : ""
        }
    }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var results: [SearchResolvedPlace] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSearching = false
    private let completer = MKLocalSearchCompleter()
    private var region = MKCoordinateRegion(
        center: .init(latitude: 23.1291, longitude: 113.2644),
        latitudinalMeters: 50_000,
        longitudinalMeters: 50_000
    )
    private var regionPriority: MKLocalSearchRegionPriority = .default
    private var mode: SearchRegionMode = .domestic
    private var acceptsCompletions = true
    private var activeSearch: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func configure(region mapRegion: MKCoordinateRegion, mode: SearchRegionMode) {
        self.mode = mode
        activeSearch?.cancel()
        activeSearch = nil
        isSearching = false
        results = []
        errorMessage = nil

        switch mode {
        case .domestic:
            region = MKCoordinateRegion(
                center: .init(latitude: 30, longitude: 105),
                span: .init(latitudeDelta: 58, longitudeDelta: 68)
            )
            regionPriority = .required
            acceptsCompletions = true
        case .international:
            if CoordinateConverter.isInChina(mapRegion.center) {
                region = MKCoordinateRegion(
                    center: .init(latitude: 0, longitude: 0),
                    span: .init(latitudeDelta: 180, longitudeDelta: 360)
                )
                regionPriority = .default
                acceptsCompletions = false
            } else {
                region = MKCoordinateRegion(
                    center: mapRegion.center,
                    span: .init(
                        latitudeDelta: max(mapRegion.span.latitudeDelta, 0.5),
                        longitudeDelta: max(mapRegion.span.longitudeDelta, 0.5)
                    )
                )
                regionPriority = .required
                acceptsCompletions = true
            }
        }

        completions = []
        completer.region = self.region
        completer.regionPriority = regionPriority
        let fragment = query
        completer.queryFragment = ""
        if acceptsCompletions { completer.queryFragment = fragment }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = acceptsCompletions ? completer.results : []
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { errorMessage = error.localizedDescription }

    func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        activeSearch?.cancel()
        errorMessage = nil
        isSearching = true

        let request = MKLocalSearch.Request(naturalLanguageQuery: text, region: region)
        request.regionPriority = mode == .domestic ? .required : .default
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self, self.activeSearch === search else { return }
                self.isSearching = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.results = response?.mapItems
                    .filter(self.matchesCurrentMode(_:))
                    .map(self.resolvedPlace(from:)) ?? []
                if self.results.isEmpty { self.errorMessage = "未找到相关地点" }
            }
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion, completionHandler: @escaping (Result<SearchResolvedPlace, Error>) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = region
        request.regionPriority = regionPriority
        MKLocalSearch(request: request).start { response, error in
            if let error { completionHandler(.failure(error)); return }
            guard let item = response?.mapItems.first else {
                completionHandler(.failure(NSError(domain: "HHJSearch", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到该地点"])))
                return
            }
            guard self.matchesCurrentMode(item) else {
                completionHandler(.failure(NSError(domain: "HHJSearch", code: 422, userInfo: [NSLocalizedDescriptionKey: "该地点不属于当前搜索区域"])))
                return
            }
            completionHandler(.success(SearchResolvedPlace(
                mapItem: item,
                title: item.name.flatMap { $0.isEmpty ? nil : $0 } ?? completion.title,
                subtitle: completion.subtitle
            )))
        }
    }

    private func resolvedPlace(from item: MKMapItem) -> SearchResolvedPlace {
        SearchResolvedPlace(
            mapItem: item,
            title: item.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? item.address?.shortAddress
                ?? "已选择的位置",
            subtitle: item.address?.fullAddress ?? ""
        )
    }

    private func matchesCurrentMode(_ item: MKMapItem) -> Bool {
        let regionCode = item.addressRepresentations?.region?.identifier ?? item.placemark.isoCountryCode
        let isDomestic = regionCode?.uppercased() == "CN"
        return mode == .domestic ? isDomestic : !isDomestic
    }
}
