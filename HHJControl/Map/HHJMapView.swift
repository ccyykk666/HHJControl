import MapKit
import SwiftUI

struct HHJMapView: UIViewRepresentable {
    @Binding var selection: LocationSelection
    var mapRequestID: UUID
    var onSelect: (CLLocationCoordinate2D, LocationSelection.Source) -> Void
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
        init(parent: HHJMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location, location.horizontalAccuracy >= 0 else { return }
            parent.onUserLocationUpdate(location)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
            if programmaticMove { programmaticMove = false; return }
            parent.onSelect(mapView.centerCoordinate, .map)
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let map = recognizer.view as? MKMapView else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            programmaticMove = true
            map.setCenter(coordinate, animated: true)
            parent.onSelect(coordinate, .longPress)
        }

    }
}
