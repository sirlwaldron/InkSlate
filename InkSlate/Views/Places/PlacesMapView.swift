import SwiftUI
import MapKit
import CoreData
import CoreLocation
import Combine
import os

fileprivate let placesMapLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "PlacesMap")

// MARK: - Place Coordinate Helpers

extension Place {
    /// 0,0 (the Core Data default) means "no coordinate captured yet"
    var hasCoordinate: Bool {
        !(latitude == 0 && longitude == 0)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Places Map View

struct PlacesMapView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest private var allPlaces: FetchedResults<Place>

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlace: Place?
    @State private var detailPlace: Place?

    init() {
        let request = NSFetchRequest<Place>(entityName: "Place")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Place.name, ascending: true)]
        request.predicate = NSPredicate(format: "latitude != 0 OR longitude != 0")
        _allPlaces = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var mappablePlaces: [Place] {
        allPlaces.filter { $0.hasCoordinate }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(mappablePlaces) { place in
                    Annotation(place.name ?? "Untitled Place", coordinate: place.coordinate) {
                        PlaceMapPin(place: place, isSelected: selectedPlace?.objectID == place.objectID)
                            .onTapGesture {
                                lightHaptic()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedPlace = place
                                }
                            }
                    }
                    .annotationTitles(.automatic)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                #if os(iOS)
                MapCompass()
                MapScaleView()
                #endif
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedPlace = nil
                }
            }

            if let place = selectedPlace {
                PlaceMapCallout(place: place) {
                    detailPlace = place
                } onDismiss: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedPlace = nil
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if mappablePlaces.isEmpty {
                emptyOverlay
            }
        }
        .navigationTitle("Map")
        .inlineNavigationTitle()
        .inkSlateSheet(item: $detailPlace) { place in
            PlaceDetailView(place: place)
        }
    }

    private var emptyOverlay: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 28))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            Text("No places on the map yet")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Text("Places appear here once they have a location. Add an address when creating or editing a place — existing addresses are located automatically in the background.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.surface.opacity(0.95))
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
        .padding(DesignSystem.Spacing.xl)
        .frame(maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }
}

// MARK: - Map Pin

struct PlaceMapPin: View {
    @ObservedObject var place: Place
    let isSelected: Bool

    private var pinColor: Color {
        Color(hex: place.category?.color ?? "") ?? DesignSystem.Colors.accent
    }

    private var pinIcon: String {
        place.category?.icon ?? "mappin"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(place.isVisited ? pinColor : pinColor.opacity(0.55))

                Image(systemName: pinIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle().stroke(.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)

            if place.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(2.5)
                    .background(DesignSystem.Colors.warning)
                    .clipShape(Circle())
                    .offset(x: 5, y: -5)
            }
        }
        .scaleEffect(isSelected ? 1.25 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Map Callout Card

struct PlaceMapCallout: View {
    @ObservedObject var place: Place
    let onDetails: () -> Void
    let onDismiss: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        if let categoryName = place.category?.name, !categoryName.isEmpty {
            parts.append(categoryName)
        }
        if let city = place.city, !city.isEmpty {
            parts.append(city)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(place.name ?? "Untitled Place")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    if place.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: DesignSystem.Spacing.xs) {
                    if place.isVisited {
                        Label("\(place.rating)/10", systemImage: "checkmark.circle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.success)
                    } else {
                        Label("Wishlist", systemImage: "star")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                }
            }

            Spacer()

            Button(action: onDetails) {
                Text("Details")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textInverse)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Address Autocomplete

/// What the autocomplete field searches for and fills its text with.
enum PlaceSearchMode {
    /// Search street addresses; picking fills the field with the formatted address.
    case address
    /// Google-style: search businesses and points of interest by name; picking fills
    /// the field with the place's name and reports its address alongside.
    case placeName
}

/// Result of the user picking a suggestion: the place details plus coordinate.
struct ResolvedPlaceAddress {
    let name: String?
    let address: String
    let city: String?
    let coordinate: CLLocationCoordinate2D
}

/// Wraps MKLocalSearchCompleter for SwiftUI.
final class PlaceAddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    init(mode: PlaceSearchMode) {
        super.init()
        completer.delegate = self
        switch mode {
        case .address:
            completer.resultTypes = [.address, .pointOfInterest]
        case .placeName:
            completer.resultTypes = [.pointOfInterest, .query]
        }
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completer.cancel()
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.cancel()
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Resolves a suggestion to a concrete coordinate + formatted address via MKLocalSearch.
    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedPlaceAddress? {
        let request = MKLocalSearch.Request(completion: completion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }
            let placemark = item.placemark

            var addressParts: [String] = []
            if let street = [placemark.subThoroughfare, placemark.thoroughfare]
                .compactMap({ $0 })
                .joined(separator: " ")
                .nilIfEmpty {
                addressParts.append(street)
            }
            if let locality = placemark.locality { addressParts.append(locality) }
            if let state = placemark.administrativeArea { addressParts.append(state) }
            if let postal = placemark.postalCode { addressParts.append(postal) }
            let formatted = addressParts.isEmpty
                ? [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                : addressParts.joined(separator: ", ")

            return ResolvedPlaceAddress(
                name: item.name,
                address: formatted,
                city: placemark.locality,
                coordinate: placemark.coordinate
            )
        } catch {
            placesMapLog.error("Address resolve failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Text field with Apple Maps suggestions. Picking a suggestion fills the field
/// (address or place name depending on mode) and reports the full resolved place;
/// typing manually reports plain edits so the caller can invalidate stale coordinates.
struct AddressAutocompleteField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var mode: PlaceSearchMode = .address
    var autoFocus: Bool = false
    /// Called when the user picks a suggestion (coordinates captured).
    let onResolved: (ResolvedPlaceAddress) -> Void
    /// Called when the user edits the text manually.
    let onManualEdit: () -> Void

    @StateObject private var completer: PlaceAddressCompleter
    @FocusState private var isFocused: Bool
    @State private var suppressSearchForNextChange = false
    @State private var isResolving = false

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        mode: PlaceSearchMode = .address,
        autoFocus: Bool = false,
        onResolved: @escaping (ResolvedPlaceAddress) -> Void,
        onManualEdit: @escaping () -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.mode = mode
        self.autoFocus = autoFocus
        self.onResolved = onResolved
        self.onManualEdit = onManualEdit
        self._completer = StateObject(wrappedValue: PlaceAddressCompleter(mode: mode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField(placeholder, text: $text)
                    .font(DesignSystem.Typography.body)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                if isResolving {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.backgroundSecondary)
            .cornerRadius(DesignSystem.CornerRadius.sm)

            if isFocused && !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(completer.results.prefix(4).enumerated()), id: \.offset) { index, result in
                        Button {
                            pick(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(DesignSystem.Typography.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)

                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < min(completer.results.count, 4) - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                )
            }
        }
        .onChange(of: text) { _, newValue in
            if suppressSearchForNextChange {
                suppressSearchForNextChange = false
                return
            }
            guard isFocused else { return }
            onManualEdit()
            completer.search(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                completer.clear()
            }
        }
        .onAppear {
            if autoFocus {
                // Slight delay so sheet presentation finishes before focusing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isFocused = true
                }
            }
        }
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        lightHaptic()
        isResolving = true
        completer.clear()
        Task { @MainActor in
            defer { isResolving = false }
            if let resolved = await completer.resolve(result) {
                suppressSearchForNextChange = true
                switch mode {
                case .address:
                    text = resolved.address
                case .placeName:
                    text = resolved.name ?? result.title
                }
                onResolved(resolved)
            }
            isFocused = false
        }
    }
}

// MARK: - Coordinate Backfill for Existing Places

/// One-at-a-time CLGeocoder backfill for places saved before coordinates were captured.
/// Runs shortly after launch; respects Apple's geocoding rate limits.
enum PlaceGeocodingBackfill {
    private static let failCountsKey = "places.geocode.failCounts"
    private static let maxFailuresPerPlace = 3
    private static let maxPlacesPerRun = 25
    private static let delayBetweenRequests: UInt64 = 1_500_000_000  // 1.5s

    @MainActor private static var isRunning = false

    @MainActor
    static func run(container: NSPersistentContainer) {
        guard !isRunning else { return }
        isRunning = true

        Task.detached(priority: .utility) {
            await backfill(container: container)
            await MainActor.run { isRunning = false }
        }
    }

    private static func backfill(container: NSPersistentContainer) async {
            let context = container.newBackgroundContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            struct Candidate {
                let objectID: NSManagedObjectID
                let key: String
                let query: String
            }

            var failCounts = UserDefaults.standard.dictionary(forKey: failCountsKey) as? [String: Int] ?? [:]

            let candidates: [Candidate] = await context.perform {
                let request = NSFetchRequest<Place>(entityName: "Place")
                request.predicate = NSPredicate(format: "latitude == 0 AND longitude == 0")
                request.fetchLimit = 200
                let places = (try? context.fetch(request)) ?? []

                return places.compactMap { place in
                    let parts = [place.address, place.city, place.state, place.country]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    guard !parts.isEmpty else { return nil }
                    let key = place.id?.uuidString ?? place.objectID.uriRepresentation().absoluteString
                    guard (failCounts[key] ?? 0) < maxFailuresPerPlace else { return nil }
                    return Candidate(objectID: place.objectID, key: key, query: parts.joined(separator: ", "))
                }
            }

            guard !candidates.isEmpty else { return }
            placesMapLog.info("Geocode backfill: \(candidates.count) place(s) missing coordinates")

            let geocoder = CLGeocoder()

            for candidate in candidates.prefix(maxPlacesPerRun) {
                do {
                    let placemarks = try await geocoder.geocodeAddressString(candidate.query)
                    guard let location = placemarks.first?.location else {
                        failCounts[candidate.key, default: 0] += 1
                        continue
                    }

                    await context.perform {
                        guard let place = try? context.existingObject(with: candidate.objectID) as? Place else { return }
                        // Don't clobber a coordinate that synced in from another device meanwhile.
                        guard place.latitude == 0 && place.longitude == 0 else { return }
                        place.latitude = location.coordinate.latitude
                        place.longitude = location.coordinate.longitude
                        place.modifiedDate = Date()
                        try? context.save()
                    }
                    failCounts.removeValue(forKey: candidate.key)
                } catch {
                    let clError = error as? CLError
                    if clError?.code == .network || clError?.code == .denied {
                        // Offline or throttled — stop and retry on a future launch without penalizing places.
                        placesMapLog.info("Geocode backfill paused: \(error.localizedDescription)")
                        break
                    }
                    failCounts[candidate.key, default: 0] += 1
                }

                try? await Task.sleep(nanoseconds: delayBetweenRequests)
            }

            UserDefaults.standard.set(failCounts, forKey: failCountsKey)
    }
}
