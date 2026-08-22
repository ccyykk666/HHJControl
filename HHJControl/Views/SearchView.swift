import MapKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = SearchService()
    @State private var regionMode: SearchRegionMode = .domestic

    var body: some View {
        NavigationStack {
            List {
                Picker("搜索区域", selection: $regionMode) {
                    ForEach(SearchRegionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                searchContent
            }
            .navigationTitle("搜索")
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "地址或地点")
            .onSubmit(of: .search) { search.submit() }
            .onAppear { configureSearch() }
            .onChange(of: regionMode) { _, _ in configureSearch() }
            .onReceive(model.$searchRegion) { _ in configureSearch() }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("搜索地点", systemImage: "magnifyingglass", description: Text("输入地址、地标或商户名称。"))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if !search.results.isEmpty {
            ForEach(search.results) { result in
                Button { choose(result) } label: {
                    searchRow(title: result.title, subtitle: result.subtitle)
                }
            }
        } else if search.completions.isEmpty {
            if let error = search.errorMessage {
                ContentUnavailableView("搜索失败", systemImage: "exclamationmark.magnifyingglass", description: Text(error))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if search.isSearching {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在搜索…")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ContentUnavailableView("暂无结果", systemImage: "magnifyingglass")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } else {
            ForEach(search.completions, id: \.self) { result in
                Button { choose(result) } label: {
                    searchRow(title: result.title, subtitle: result.subtitle)
                }
            }
        }
    }

    private func searchRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.primary)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func configureSearch() {
        search.configure(region: model.searchRegion, mode: regionMode)
    }

    private func choose(_ result: SearchResolvedPlace) {
        if let item = result.mapItem {
            model.select(item, title: result.title, regionFallback: result.subtitle)
        } else {
            model.selectResolvedSearch(
                coordinate: result.coordinate,
                title: result.title,
                administrativeArea: result.administrativeArea
            )
        }
        model.selectedTab = .location
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        search.resolve(completion) { result in
            Task { @MainActor in
                switch result {
                case .success(let value):
                    choose(value)
                case .failure(let error): model.notice = error.localizedDescription
                }
            }
        }
    }
}
