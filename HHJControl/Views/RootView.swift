import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    var body: some View {
        RootTabBarControllerHost(model: model)
            .sheet(
                isPresented: Binding(get: { !didCompleteOnboarding }, set: { if !$0 { didCompleteOnboarding = true } }),
                onDismiss: { model.prepareForLaunch() }
            ) {
                OnboardingView { didCompleteOnboarding = true }
                    .presentationSizing(.form.fitted(horizontal: false, vertical: true))
            }
            .onAppear {
                if didCompleteOnboarding { model.prepareForLaunch() }
            }
            .alert("提示", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("好", role: .cancel) { model.notice = nil }
            } message: { Text(model.notice ?? "") }
    }
}
