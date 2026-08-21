import SwiftUI
import UIKit

struct SearchTabReselectionObserver: UIViewRepresentable {
    var onReselect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onReselect = onReselect
        DispatchQueue.main.async {
            context.coordinator.attach(from: uiView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onReselect: () -> Void
        private weak var tabBar: UITabBar?
        private var tapRecognizer: UITapGestureRecognizer?

        init(onReselect: @escaping () -> Void) {
            self.onReselect = onReselect
        }

        func attach(from view: UIView) {
            guard let rootViewController = view.window?.rootViewController,
                  let controller = findTabBarController(in: rootViewController),
                  controller.tabBar !== tabBar else { return }
            if let tapRecognizer {
                tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
            }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(didTapSearchTab))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            controller.tabBar.addGestureRecognizer(recognizer)
            tabBar = controller.tabBar
            tapRecognizer = recognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let tapRecognizer = gestureRecognizer as? UITapGestureRecognizer,
                  let tabBar,
                  let items = tabBar.items,
                  let searchIndex = items.firstIndex(where: { $0.title == "搜索" }),
                  tabBar.selectedItem === items[searchIndex] else { return false }
            return searchItemFrame(in: tabBar, at: searchIndex, itemCount: items.count).contains(tapRecognizer.location(in: tabBar))
        }

        @objc private func didTapSearchTab() {
            onReselect()
        }

        private func searchItemFrame(in tabBar: UITabBar, at index: Int, itemCount: Int) -> CGRect {
            let width = tabBar.itemWidth > 0 ? tabBar.itemWidth : tabBar.bounds.width / CGFloat(itemCount)
            let spacing = tabBar.itemSpacing > 0 ? tabBar.itemSpacing : 0
            let totalWidth = width * CGFloat(itemCount) + spacing * CGFloat(itemCount - 1)
            let origin = (tabBar.bounds.width - totalWidth) / 2
            return CGRect(x: origin + CGFloat(index) * (width + spacing), y: 0, width: width, height: tabBar.bounds.height)
        }

        private func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
            if let tabBarController = viewController as? UITabBarController { return tabBarController }
            for child in viewController.children {
                if let tabBarController = findTabBarController(in: child) { return tabBarController }
            }
            return nil
        }
    }
}
