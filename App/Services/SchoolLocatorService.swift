import Combine
import CoreLocation
import Foundation

enum SchoolLocatorError: LocalizedError {
    case permissionDenied, unavailable, addressNotFound, emptyAddress, timedOut, busy, cancelled
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "La localisation n’est pas autorisée. Vous pouvez rechercher une ville ou saisir directement l’adresse PRONOTE."
        case .unavailable: return "La position n’est pas disponible. Essayez une ville ou un code postal."
        case .addressNotFound: return "Cette ville ou adresse n’a pas été trouvée. Précisez le code postal ou saisissez l’adresse PRONOTE."
        case .emptyAddress: return "Indiquez une ville, un code postal ou une adresse."
        case .timedOut: return "La localisation prend trop de temps. Essayez une recherche par ville."
        case .busy: return "Une recherche est déjà en cours."
        case .cancelled: return "Recherche annulée."
        }
    }
}

/// A one-shot, user-requested lookup. No coordinates or addresses are persisted.
@MainActor
final class SchoolLocatorService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var pending: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var pendingID: UUID?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A broad position is enough to find schools; precise tracking is unnecessary.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func currentCoordinates() async throws -> CLLocationCoordinate2D {
        guard pending == nil else { throw SchoolLocatorError.busy }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation; pendingID = id
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) }
                    catch { return }
                    guard let self, self.pendingID == id else { return }
                    self.finish(.failure(SchoolLocatorError.timedOut))
                }
                authorizationChanged()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.pendingID == id else { return }
                self.finish(.failure(SchoolLocatorError.cancelled))
            }
        }
    }

    func coordinates(for address: String) async throws -> CLLocationCoordinate2D {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 300 else { throw SchoolLocatorError.emptyAddress }
        try Task.checkCancellation()
        do {
            let places = try await geocoder.geocodeAddressString(clean)
            try Task.checkCancellation()
            guard let coordinate = places.compactMap(\.location).first?.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else { throw SchoolLocatorError.addressNotFound }
            return coordinate
        } catch is CancellationError { throw SchoolLocatorError.cancelled }
        catch let error as SchoolLocatorError { throw error }
        catch { throw SchoolLocatorError.addressNotFound }
    }

    func cancel() {
        geocoder.cancelGeocode()
        if pending != nil { finish(.failure(SchoolLocatorError.cancelled)) }
    }

    private func authorizationChanged() {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(.failure(SchoolLocatorError.permissionDenied))
        @unknown default: finish(.failure(SchoolLocatorError.unavailable))
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation = pending else { return }
        pending = nil; pendingID = nil
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 }),
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor [weak self] in
            self?.finish(.success(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            self?.finish(.failure(denied ? SchoolLocatorError.permissionDenied : SchoolLocatorError.unavailable))
        }
    }
}
