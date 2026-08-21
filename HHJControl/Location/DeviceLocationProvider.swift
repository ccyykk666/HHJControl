import CoreLocation
import Foundation

@MainActor
final class DeviceLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied, unavailable
        var errorDescription: String? {
            switch self { case .denied: "定位权限已关闭，请前往系统设置授权"; case .unavailable: "暂时无法获取当前位置" }
        }
    }

    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(.failure(LocationError.denied))
        @unknown default: finish(.failure(LocationError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { finish(.failure(LocationError.denied)) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { finish(.failure(LocationError.unavailable)); return }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<CLLocation, Error>) { completion?(result); completion = nil }
}
