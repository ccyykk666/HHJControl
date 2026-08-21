import MapKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = SearchService()

    var body: some View {
        NavigationStack {
            Group {
                if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("搜索地点", systemImage: "magnifyingglass", description: Text("输入地址、地标或商户名称。"))
                } else if search.completions.isEmpty {
                    if let error = search.errorMessage { ContentUnavailableView("搜索失败", systemImage: "exclamationmark.magnifyingglass", description: Text(error)) }
                    else { ProgressView("正在搜索…") }
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
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        search.resolve(completion) { result in
            Task { @MainActor in
                switch result {
                case .success(let value):
                    model.select(value.0, address: value.1, source: .search)
                    model.selectedTab = .location
                case .failure(let error): model.notice = error.localizedDescription
                }
            }
        }
    }
}

