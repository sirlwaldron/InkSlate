import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

content = content.replace(".onChange(of: selectedFeature) { _, feature in", ".onChange(of: selectedFeature) { feature in")

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)
print("Patched onChange successfully.")
