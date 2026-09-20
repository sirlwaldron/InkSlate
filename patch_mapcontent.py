import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

old_block = """    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, selection: $selectedFeature) {
                UserAnnotation()
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
            .mapStyle(.standard(pointsOfInterest: .all))"""

new_block = """    @MapContentBuilder
    private var mapContent: some MapContent {
        UserAnnotation()
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

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, selection: $selectedFeature) {
                mapContent
            }
            .mapStyle(.standard(pointsOfInterest: .all))"""

content = content.replace(old_block, new_block)

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)
print("Patched mapContent successfully.")
