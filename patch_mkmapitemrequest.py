import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

content = content.replace("let req = MKMapItemRequest(mapFeature: feature)", "let req = MKMapItemRequest(feature: feature)")

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)
print("Patched MKMapItemRequest successfully.")
