import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    let model: AppModel

    override init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
            if ProcessInfo.processInfo.arguments.contains("-reset-state"),
               let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                try? FileManager.default.removeItem(at: support.appendingPathComponent("HHJControl", isDirectory: true))
            }
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            model = AppModel(bluetooth: HHJBluetoothController(transport: InactiveBluetoothTransport()))
        } else {
            model = AppModel()
        }
        super.init()
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
