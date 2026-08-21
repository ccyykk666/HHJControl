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
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: beginUpdatingLocation()
        case .denied, .restricted: finish(.failure(LocationError.denied))
        @unknown default: finish(.failure(LocationError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { beginUpdatingLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { finish(.failure(LocationError.denied)) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) <= 15
        }) else { return }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown { return }
        finish(.failure(error))
    }

    private func beginUpdatingLocation() {
        manager.startUpdatingLocation()
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(LocationError.unavailable))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        completion?(result)
        completion = nil
    }
}
