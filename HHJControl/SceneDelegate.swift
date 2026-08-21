import MapKit
import SwiftUI
import UIKit

private final class SoftEdgeHostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySoftTopEdgeEffect(in: view.window ?? view)
    }

    private func applySoftTopEdgeEffect(in currentView: UIView) {
        if let scrollView = currentView as? UIScrollView,
           !isInsideMap(scrollView) {
            scrollView.topEdgeEffect.style = .soft
        }

        for subview in currentView.subviews {
            applySoftTopEdgeEffect(in: subview)
        }
    }

    private func isInsideMap(_ view: UIView) -> Bool {
        var ancestor = view.superview
        while let current = ancestor {
            if current is MKMapView { return true }
            ancestor = current.superview
        }
        return false
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let root = RootView()
            .environmentObject(appDelegate.model)
            .environmentObject(appDelegate.model.bluetooth)
            .environmentObject(appDelegate.model.store)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = SoftEdgeHostingController(rootView: root)
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let model = (UIApplication.shared.delegate as? AppDelegate)?.model else { return }
        model.bluetooth.setForeground(true)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? AppDelegate)?.model.bluetooth.setForeground(false)
    }
}
