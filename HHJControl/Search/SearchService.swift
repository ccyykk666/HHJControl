import MapKit
import SwiftUI

struct SearchResolvedPlace: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    let title: String
    let subtitle: String
}

@MainActor
final class SearchService: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            results = []
            errorMessage = nil
            completer.queryFragment = query
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
    private var activeSearch: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func configure(region: MKCoordinateRegion) {
        let minimumSpan = MKCoordinateSpan(
            latitudeDelta: max(region.span.latitudeDelta, 0.5),
            longitudeDelta: max(region.span.longitudeDelta, 0.5)
        )
        self.region = MKCoordinateRegion(center: region.center, span: minimumSpan)
        regionPriority = CoordinateConverter.isInChina(region.center) ? .default : .required
        completer.region = self.region
        completer.regionPriority = regionPriority
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { completions = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { errorMessage = error.localizedDescription }

    func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        activeSearch?.cancel()
        errorMessage = nil
        isSearching = true

        let request = MKLocalSearch.Request(naturalLanguageQuery: text, region: region)
        request.regionPriority = .default
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
                self.results = response?.mapItems.map(self.resolvedPlace(from:)) ?? []
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
}
