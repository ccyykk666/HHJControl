import MapKit
import SwiftUI

struct SearchResolvedPlace: Identifiable {
    let id: String
    let mapItem: MKMapItem?
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let administrativeArea: String?
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
            searchTask?.cancel()
            activeSearch?.cancel()
            activeSearch = nil
            isSearching = false
            results = []
            errorMessage = nil
            completer.queryFragment = acceptsCompletions ? query : ""
            if !acceptsCompletions { scheduleSearch() }
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
    private var searchTask: Task<Void, Never>?
    private let geoapify = GeoapifyService()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func configure(region mapRegion: MKCoordinateRegion, mode: SearchRegionMode) {
        self.mode = mode
        searchTask?.cancel()
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
            region = mapRegion
            regionPriority = .default
            acceptsCompletions = false
        }

        completions = []
        completer.region = self.region
        completer.regionPriority = regionPriority
        let fragment = query
        completer.queryFragment = ""
        if acceptsCompletions {
            completer.queryFragment = fragment
        } else {
            scheduleSearch()
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = acceptsCompletions ? completer.results : []
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { errorMessage = error.localizedDescription }

    func submit() {
        searchTask?.cancel()
        if mode == .domestic { performDomesticSearch() }
        else { performInternationalSearch() }
    }

    private func scheduleSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            await self.performInternationalSearch(text: text)
        }
    }

    private func performDomesticSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        activeSearch?.cancel()
        errorMessage = nil
        isSearching = true

        let request = MKLocalSearch.Request(naturalLanguageQuery: text, region: region)
        request.regionPriority = regionPriority
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

    private func performInternationalSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.performInternationalSearch(text: text)
        }
    }

    private func performInternationalSearch(text: String) async {
        errorMessage = nil
        isSearching = true
        do {
            let bias = CoordinateConverter.isInChina(region.center) ? nil : region.center
            let places = try await geoapify.search(text, bias: bias)
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            results = places.map {
                SearchResolvedPlace(
                    id: $0.id,
                    mapItem: nil,
                    coordinate: $0.coordinate,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    administrativeArea: $0.administrativeArea
                )
            }
            if results.isEmpty { errorMessage = "未找到相关地点" }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isSearching = false
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
                id: UUID().uuidString,
                mapItem: item,
                coordinate: item.location.coordinate,
                title: item.name.flatMap { $0.isEmpty ? nil : $0 } ?? completion.title,
                subtitle: completion.subtitle,
                administrativeArea: nil
            )))
        }
    }

    private func resolvedPlace(from item: MKMapItem) -> SearchResolvedPlace {
        SearchResolvedPlace(
            id: UUID().uuidString,
            mapItem: item,
            coordinate: item.location.coordinate,
            title: item.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? item.address?.shortAddress
                ?? "已选择的位置",
            subtitle: item.address?.fullAddress ?? "",
            administrativeArea: nil
        )
    }
}
