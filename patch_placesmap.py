import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

# Add states
old_states = """    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlace: Place?
    @State private var detailPlace: Place?

    init() {"""
new_states = """    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlace: Place?
    @State private var detailPlace: Place?
    @State private var selectedFeature: MapFeature?
    @State private var resolvedItem: MKMapItem?
    @State private var isResolvingFeature = false
    @StateObject private var locationManager = LocationManager.shared

    init() {"""
content = content.replace(old_states, new_states)

# Add MapFeature selection
old_map = """            Map(position: $cameraPosition) {
                ForEach(mappablePlaces) { place in"""
new_map = """            Map(position: $cameraPosition, selection: $selectedFeature) {
                UserAnnotation()
                ForEach(mappablePlaces) { place in"""
content = content.replace(old_map, new_map)

# Add mapStyle and mapControls
old_controls = """            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                #if os(iOS)
                MapCompass()
                MapScaleView()
                #endif
            }
            .onTapGesture {"""
new_controls = """            }
            .mapStyle(.standard(pointsOfInterest: .all))
            .mapControls {
                #if os(iOS)
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
                #endif
            }
            .onChange(of: selectedFeature) { _, feature in
                if let feature = feature {
                    isResolvingFeature = true
                    selectedPlace = nil
                    Task {
                        let req = MKMapItemRequest(mapFeature: feature)
                        if let item = try? await req.mapItem {
                            await MainActor.run {
                                resolvedItem = item
                                isResolvingFeature = false
                            }
                        } else {
                            await MainActor.run { isResolvingFeature = false }
                        }
                    }
                } else {
                    resolvedItem = nil
                }
            }
            .onAppear {
                locationManager.requestAuthorization()
            }
            .onTapGesture {"""
content = content.replace(old_controls, new_controls)

# Add resolvedItem callout
old_empty = """            if mappablePlaces.isEmpty {
                emptyOverlay
            }
        }
        .navigationTitle("Map")"""
new_empty = """            if mappablePlaces.isEmpty && resolvedItem == nil && selectedPlace == nil {
                emptyOverlay
            }

            if let item = resolvedItem {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Unknown Place")
                                .font(.headline)
                            if let category = item.pointOfInterestCategory?.rawValue {
                                Text(category.replacingOccurrences(of: "MKPOICategory", with: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            withAnimation {
                                selectedFeature = nil
                                resolvedItem = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    Button(action: {
                        let newPlace = Place(context: viewContext)
                        newPlace.id = UUID()
                        newPlace.name = item.name ?? "New Place"
                        newPlace.latitude = item.placemark.coordinate.latitude
                        newPlace.longitude = item.placemark.coordinate.longitude
                        if let address = item.placemark.title {
                            newPlace.address = address
                        }
                        newPlace.createdDate = Date()
                        newPlace.modifiedDate = Date()
                        detailPlace = newPlace
                        selectedFeature = nil
                        resolvedItem = nil
                    }) {
                        Text("Add to Places")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.md)
                .shadow(radius: 5)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Map")"""
content = content.replace(old_empty, new_empty)

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)
print("Patched PlacesMapView.swift successfully.")
