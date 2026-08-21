import MapKit
import SwiftUI

@MainActor
final class SearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var errorMessage: String?
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { completions = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { errorMessage = error.localizedDescription }

    func resolve(_ completion: MKLocalSearchCompletion, completionHandler: @escaping (Result<(CLLocationCoordinate2D, String), Error>) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, error in
            if let error { completionHandler(.failure(error)); return }
            guard let item = response?.mapItems.first else {
                completionHandler(.failure(NSError(domain: "HHJSearch", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到该地点"])))
                return
            }
            let title = [item.name, completion.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
            completionHandler(.success((item.location.coordinate, title)))
        }
    }
}

