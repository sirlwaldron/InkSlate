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
    private let modifiedKey = "InkSlate_SavedLocations_Modified"
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
    
    private struct Snapshot {
        var locations: [SavedLocation]
        var activeID: UUID?
        var modified: TimeInterval
    }

    private func readSnapshot(locationsData: Data?, activeString: String?, modified: Double) -> Snapshot? {
        guard let data = locationsData,
              let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) else { return nil }
        return Snapshot(locations: decoded, activeID: activeString.flatMap(UUID.init(uuidString:)), modified: modified)
    }

    /// Loads locations from iCloud KVS and UserDefaults. The copy with the newest modification
    /// timestamp wins, so an empty list (everything deleted) propagates between devices instead of
    /// being overwritten by a stale non-empty copy. Data from before timestamps existed counts as
    /// timestamp 0, and a tie prefers a non-empty iCloud copy, then the local one.
    private func load() {
        let cloud = readSnapshot(
            locationsData: cloudStore.data(forKey: defaultsKey),
            activeString: cloudStore.string(forKey: activeKey),
            modified: cloudStore.double(forKey: modifiedKey)
        )
        let local = readSnapshot(
            locationsData: userDefaults.data(forKey: defaultsKey),
            activeString: userDefaults.string(forKey: activeKey),
            modified: userDefaults.double(forKey: modifiedKey)
        )

        let chosen: (snapshot: Snapshot, fromCloud: Bool)? = {
            switch (cloud, local) {
            case let (c?, l?):
                if c.modified > l.modified { return (c, true) }
                if l.modified > c.modified { return (l, false) }
                return (!c.locations.isEmpty || l.locations.isEmpty) ? (c, true) : (l, false)
            case let (c?, nil):
                return (c, true)
            case let (nil, l?):
                return (l, false)
            case (nil, nil):
                return nil
            }
        }()
        guard let chosen else { return }
        let winner = chosen.snapshot
        let cloudWon = chosen.fromCloud

        if locations != winner.locations { locations = winner.locations }
        if activeLocationId != winner.activeID { activeLocationId = winner.activeID }

        // Bring the losing store in line with the winner (no timestamp bump, so this can't ping-pong).
        persist(winner, toCloud: !cloudWon, toLocal: cloudWon)
    }

    private func persist(_ snapshot: Snapshot, toCloud: Bool, toLocal: Bool) {
        guard let encoded = try? JSONEncoder().encode(snapshot.locations) else { return }
        if toLocal {
            userDefaults.set(encoded, forKey: defaultsKey)
            userDefaults.set(snapshot.modified, forKey: modifiedKey)
            if let id = snapshot.activeID {
                userDefaults.set(id.uuidString, forKey: activeKey)
            } else {
                userDefaults.removeObject(forKey: activeKey)
            }
        }
        if toCloud {
            cloudStore.set(encoded, forKey: defaultsKey)
            cloudStore.set(snapshot.modified, forKey: modifiedKey)
            if let id = snapshot.activeID {
                cloudStore.set(id.uuidString, forKey: activeKey)
            } else {
                cloudStore.removeObject(forKey: activeKey)
            }
            cloudStore.synchronize()
        }
    }

    private func save() {
        let snapshot = Snapshot(
            locations: locations,
            activeID: activeLocationId,
            modified: Date().timeIntervalSince1970
        )
        persist(snapshot, toCloud: true, toLocal: true)
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
