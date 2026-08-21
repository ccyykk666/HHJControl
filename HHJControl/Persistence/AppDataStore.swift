import Foundation
import SwiftUI

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var favorites: [SavedPlace] = []
    @Published private(set) var records: [LocationRecord] = []

    private let directory: URL
    private var favoritesURL: URL { directory.appendingPathComponent("favorites.json") }
    private var recordsURL: URL { directory.appendingPathComponent("records.json") }
    private let encoder: JSONEncoder = { let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value }()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = applicationSupport.appendingPathComponent("HHJControl", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        favorites = (try? load([SavedPlace].self, from: favoritesURL)) ?? []
        records = (try? load([LocationRecord].self, from: recordsURL)) ?? []
    }

    func addFavorite(_ selection: LocationSelection, name: String? = nil) {
        favorites.insert(SavedPlace(name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? selection.address, selection: selection), at: 0)
        persist(favorites, to: favoritesURL)
    }

    func updateFavorite(_ place: SavedPlace) {
        guard let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index] = place
        persist(favorites, to: favoritesURL)
    }

    func removeFavorite(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persist(favorites, to: favoritesURL)
    }

    func addRecord(_ record: LocationRecord) {
        records.insert(record, at: 0)
        if records.count > 100 { records.removeLast(records.count - 100) }
        persist(records, to: recordsURL)
    }

    func removeRecord(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        persist(records, to: recordsURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
