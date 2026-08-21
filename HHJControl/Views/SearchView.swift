import MapKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = SearchService()
    @State private var regionMode: SearchRegionMode = .domestic
    private var usesUITestFixture: Bool { ProcessInfo.processInfo.environment["UITEST_SEARCH_FIXTURE"] == "1" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("搜索区域", selection: $regionMode) {
                    ForEach(SearchRegionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

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

                if regionMode == .international {
                    Link("Powered by Geoapify", destination: URL(string: "https://www.geoapify.com/")!)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "地址或地点")
            .onSubmit(of: .search) { search.submit() }
            .onAppear { configureSearch() }
            .onChange(of: regionMode) { _, _ in configureSearch() }
            .onReceive(model.$searchRegion) { _ in configureSearch() }
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
