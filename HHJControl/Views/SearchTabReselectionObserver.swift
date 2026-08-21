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
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: () -> Void
        private weak var tabBarController: UITabBarController?
        private var originalDelegate: (any UITabBarControllerDelegate)?

        init(onReselect: @escaping () -> Void) {
            self.onReselect = onReselect
        }

        func attach(from view: UIView) {
            guard let rootViewController = view.window?.rootViewController,
                  let controller = findTabBarController(in: rootViewController),
                  controller.delegate !== self else { return }
            originalDelegate = controller.delegate
            tabBarController = controller
            controller.delegate = self
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            let allowed = originalDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
            if allowed,
               tabBarController.selectedViewController === viewController,
               tabBarController.viewControllers?.firstIndex(of: viewController) == 3 {
                onReselect()
            }
            return allowed
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            originalDelegate?.tabBarController?(tabBarController, didSelect: viewController)
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
