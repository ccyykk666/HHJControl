import SwiftUI

struct FavoritesView: View {
    enum Segment: String, CaseIterable, Identifiable { case favorites = "收藏", recent = "最近"; var id: Self { self } }
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AppDataStore
    @State private var segment: Segment = .favorites
    @State private var editingPlace: SavedPlace?

    var body: some View {
        NavigationStack {
            List {
                Picker("内容", selection: $segment) { ForEach(Segment.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                if segment == .favorites {
                    favoritesList
                } else {
                    recordsList
                }
            }
            .navigationTitle("地点")
            .sheet(item: $editingPlace) { place in FavoriteEditor(place: place) }
        }
    }

    @ViewBuilder
    private var favoritesList: some View {
        if store.favorites.isEmpty {
            ContentUnavailableView("暂无收藏", systemImage: "star")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(store.favorites) { place in
                Button { model.load(place.selection) } label: {
                    PlaceRow(title: place.name, selection: place.selection, trailing: nil)
                }.swipeActions(edge: .leading) {
                    Button("编辑") { editingPlace = place }.tint(.blue)
                }
            }
            .onDelete(perform: store.removeFavorite)
        }
    }

    @ViewBuilder
    private var recordsList: some View {
        if store.records.isEmpty {
            ContentUnavailableView("暂无记录", systemImage: "clock")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(store.records) { record in
                Button { model.load(record.selection) } label: {
                    PlaceRow(title: record.selection.address, selection: record.selection, trailing: record.result == .success ? "成功" : "失败")
                }
            }
            .onDelete(perform: store.removeRecord)
        }
    }
}

private struct PlaceRow: View {
    var title: String
    var selection: LocationSelection
    var trailing: String?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(String(format: "%.6f, %.6f · %.1f m", selection.wgs84Latitude, selection.wgs84Longitude, selection.altitude))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct FavoriteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @State var place: SavedPlace
    @State private var altitude = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $place.name)
                TextField("海拔 -500...9000", text: $altitude).keyboardType(.numbersAndPunctuation)
            }
            .navigationTitle("编辑收藏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let value = Double(altitude), (-500...9000).contains(value), !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        place.selection.altitude = value
                        store.updateFavorite(place); dismiss()
                    } label: { Image(systemName: "checkmark") }
                }
            }
            .onAppear { altitude = String(format: "%.1f", place.selection.altitude) }
        }
    }
}
