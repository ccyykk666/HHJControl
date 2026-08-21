import MapKit
import SwiftUI

struct HHJMapView: UIViewRepresentable {
    @Binding var selection: LocationSelection
    var mapRequestID: UUID
    var onSelect: (CLLocationCoordinate2D, LocationSelection.Source, Duration) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onUserLocationUpdate: (CLLocation) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.showsUserLocation = true
        map.pointOfInterestFilter = .includingAll
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)
        map.setRegion(.init(center: selection.mapCoordinate, latitudinalMeters: 1_000, longitudinalMeters: 1_000), animated: false)
        context.coordinator.lastRequestID = mapRequestID
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastRequestID != mapRequestID {
            context.coordinator.lastRequestID = mapRequestID
            context.coordinator.programmaticMove = true
            if selection.source == .currentLocation {
                map.setRegion(.init(center: selection.mapCoordinate, latitudinalMeters: 1_000, longitudinalMeters: 1_000), animated: true)
            } else {
                map.setCenter(selection.mapCoordinate, animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HHJMapView
        var lastRequestID: UUID?
        var programmaticMove = false
        var regionSelectionTask: Task<Void, Never>?
        init(parent: HHJMapView) { self.parent = parent }

        deinit {
            regionSelectionTask?.cancel()
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location, location.horizontalAccuracy >= 0 else { return }
            parent.onUserLocationUpdate(location)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            regionSelectionTask?.cancel()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
            regionSelectionTask?.cancel()
            if programmaticMove { programmaticMove = false; return }
            let coordinate = mapView.centerCoordinate
            regionSelectionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1_200))
                guard !Task.isCancelled else { return }
                self?.parent.onSelect(coordinate, .map, .zero)
            }
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let map = recognizer.view as? MKMapView else { return }
            regionSelectionTask?.cancel()
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            programmaticMove = true
            map.setCenter(coordinate, animated: true)
            parent.onSelect(coordinate, .longPress, .milliseconds(800))
        }

    }
}
