import Foundation
import CoreLocation
import SwiftUI

struct SavedLocation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

class SavedLocationManager: ObservableObject {
    static let shared = SavedLocationManager()
    
    @Published var locations: [SavedLocation] = []
    @Published var activeLocationId: UUID?
    
    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let defaultsKey = "InkSlate_SavedLocations"
    private let activeKey = "InkSlate_ActiveLocation"
    private var cloudStoreObserver: NSObjectProtocol?
    
    init() {
        load()
        cloudStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }
    
    deinit {
        if let observer = cloudStoreObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    var activeLocation: SavedLocation? {
        if let id = activeLocationId, let loc = locations.first(where: { $0.id == id }) {
            return loc
        }
        return locations.first
    }
    
    func addLocation(name: String, address: String?, coordinate: CLLocationCoordinate2D) {
        let loc = SavedLocation(name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
        locations.append(loc)
        if activeLocationId == nil {
            activeLocationId = loc.id
        }
        save()
    }
    
    func updateLocation(id: UUID, name: String, address: String?, coordinate: CLLocationCoordinate2D) {
        if let index = locations.firstIndex(where: { $0.id == id }) {
            locations[index].name = name
            locations[index].address = address
            locations[index].latitude = coordinate.latitude
            locations[index].longitude = coordinate.longitude
            save()
        }
    }
    
    func removeLocation(id: UUID) {
        locations.removeAll { $0.id == id }
        if activeLocationId == id {
            activeLocationId = locations.first?.id
        }
        save()
    }
    
    func setActiveLocation(id: UUID) {
        activeLocationId = id
        save()
    }
    
    private func load() {
        var loadedLocations: [SavedLocation]? = nil
        if let cloudData = cloudStore.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: cloudData),
           !decoded.isEmpty {
            loadedLocations = decoded
        } else if let localData = userDefaults.data(forKey: defaultsKey),
                  let decoded = try? JSONDecoder().decode([SavedLocation].self, from: localData) {
            loadedLocations = decoded
            if let cloudEncoded = try? JSONEncoder().encode(decoded) {
                cloudStore.set(cloudEncoded, forKey: defaultsKey)
                cloudStore.synchronize()
            }
        }
        
        if let locs = loadedLocations {
            locations = locs
        }
        
        if let cloudActive = cloudStore.string(forKey: activeKey), let id = UUID(uuidString: cloudActive) {
            activeLocationId = id
        } else if let localActive = userDefaults.string(forKey: activeKey), let id = UUID(uuidString: localActive) {
            activeLocationId = id
            cloudStore.set(localActive, forKey: activeKey)
            cloudStore.synchronize()
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(locations) {
            userDefaults.set(encoded, forKey: defaultsKey)
            cloudStore.set(encoded, forKey: defaultsKey)
        }
        if let activeId = activeLocationId {
            userDefaults.set(activeId.uuidString, forKey: activeKey)
            cloudStore.set(activeId.uuidString, forKey: activeKey)
        } else {
            userDefaults.removeObject(forKey: activeKey)
            cloudStore.removeObject(forKey: activeKey)
        }
        cloudStore.synchronize()
    }
    
    func distanceTo(latitude: Double, longitude: Double) -> Double? {
        guard let active = activeLocation else { return nil }
        let from = CLLocation(latitude: active.latitude, longitude: active.longitude)
        let to = CLLocation(latitude: latitude, longitude: longitude)
        return from.distance(from: to) // in meters
    }
    
    func formattedDistance(to latitude: Double, longitude: Double) -> String? {
        guard let meters = distanceTo(latitude: latitude, longitude: longitude) else { return nil }
        let miles = meters / 1609.34
        if miles < 0.1 {
            let feet = meters * 3.28084
            return String(format: "%.0f ft away", feet)
        }
        return String(format: "%.1f mi away", miles)
    }
}
