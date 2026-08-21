import MapKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = SearchService()
    private var usesUITestFixture: Bool { ProcessInfo.processInfo.environment["UITEST_SEARCH_FIXTURE"] == "1" }

    var body: some View {
        NavigationStack {
            Group {
                if usesUITestFixture {
                    List {
                        Button("测试地点") {
                            model.select(.init(latitude: 31.2304, longitude: 121.4737), address: "测试地点", source: .search)
                            model.selectedTab = .location
                        }
                        .accessibilityIdentifier("search.fixture.result")
                    }
                } else if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("搜索地点", systemImage: "magnifyingglass", description: Text("输入地址、地标或商户名称。"))
                } else if !search.results.isEmpty {
                    List(search.results) { result in
                        Button { choose(result) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if search.completions.isEmpty {
                    if let error = search.errorMessage { ContentUnavailableView("搜索失败", systemImage: "exclamationmark.magnifyingglass", description: Text(error)) }
                    else if search.isSearching { ProgressView("正在搜索…") }
                    else { ContentUnavailableView("暂无结果", systemImage: "magnifyingglass") }
                } else {
                    List(search.completions, id: \.self) { result in
                        Button { choose(result) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty { Text(result.subtitle).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "地址或地点")
            .onSubmit(of: .search) { search.submit() }
            .onAppear { search.configure(region: model.searchRegion) }
        }
    }

    private func choose(_ result: SearchResolvedPlace) {
        model.select(result.mapItem, title: result.title, regionFallback: result.subtitle)
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
