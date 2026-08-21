import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    let model: AppModel

    override init() {
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
