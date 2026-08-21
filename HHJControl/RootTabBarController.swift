import Combine
import SwiftUI
import UIKit

@MainActor
final class RootTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let model: AppModel
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            hostingController(LocationView(), title: "定位", image: "location.fill"),
            hostingController(FavoritesView(), title: "收藏", image: "star.fill"),
            hostingController(AdvancedView(), title: "高级", image: "slider.horizontal.3"),
            hostingController(SearchView(), title: "搜索", image: "magnifyingglass")
        ]
        delegate = self
        selectedIndex = index(for: model.selectedTab)

        model.$selectedTab
            .removeDuplicates()
            .sink { [weak self] tab in
                guard let self else { return }
                let index = self.index(for: tab)
                if self.selectedIndex != index { self.selectedIndex = index }
            }
            .store(in: &subscriptions)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let tab = tab(for: selectedIndex)
        let wasAlreadySelected = model.selectedTab == tab
        model.selectedTab = tab
        if tab == .search, wasAlreadySelected {
            model.focusSearch()
        }
    }

    private func hostingController<Content: View>(_ content: Content, title: String, image: String) -> UIViewController {
        let rootView = content
            .environmentObject(model)
            .environmentObject(model.bluetooth)
            .environmentObject(model.store)
        let controller = UIHostingController(rootView: rootView)
        controller.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: nil)
        return controller
    }

    private func tab(for index: Int) -> AppModel.Tab {
        switch index {
        case 1: return .favorites
        case 2: return .advanced
        case 3: return .search
        default: return .location
        }
    }

    private func index(for tab: AppModel.Tab) -> Int {
        switch tab {
        case .location: return 0
        case .favorites: return 1
        case .advanced: return 2
        case .search: return 3
        }
    }
}

struct RootTabBarControllerHost: UIViewControllerRepresentable {
    let model: AppModel

    func makeUIViewController(context: Context) -> RootTabBarController {
        RootTabBarController(model: model)
    }

    func updateUIViewController(_ uiViewController: RootTabBarController, context: Context) {}
}
