import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

old_block = """                        newPlace.createdDate = Date()
                        newPlace.modifiedDate = Date()
                        detailPlace = newPlace
                        selectedFeature = nil"""

new_block = """                        newPlace.createdDate = Date()
                        newPlace.modifiedDate = Date()
                        _ = viewContext.inkSlateSave(module: "PlacesMap")
                        detailPlace = newPlace
                        selectedFeature = nil"""

content = content.replace(old_block, new_block)

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)

print("Patched PlacesMapView.swift save successfully.")
