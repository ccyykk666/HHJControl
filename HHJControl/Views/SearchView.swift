import MapKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var search: SearchService
    @State private var regionMode: SearchRegionMode = .domestic

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
                    if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        else if search.isSearching {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("正在搜索…")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                        }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("搜索")
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
