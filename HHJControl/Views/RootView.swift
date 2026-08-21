import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab("定位", systemImage: "location.fill", value: AppModel.Tab.location) { LocationView() }
            Tab("收藏", systemImage: "star.fill", value: AppModel.Tab.favorites) { FavoritesView() }
            Tab("高级", systemImage: "slider.horizontal.3", value: AppModel.Tab.advanced) { AdvancedView() }
            Tab(value: AppModel.Tab.search, role: .search) { SearchView() }
        }
        .sheet(isPresented: Binding(get: { !didCompleteOnboarding }, set: { if !$0 { didCompleteOnboarding = true } })) {
            OnboardingView { didCompleteOnboarding = true }
        }
        .alert("提示", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好", role: .cancel) { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }
}
