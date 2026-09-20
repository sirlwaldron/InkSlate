import re

with open("InkSlate/Views/Places/PlacesMapView.swift", "r") as f:
    content = f.read()

old_block = """            .onChange(of: selectedFeature) { feature in
                if let feature = feature {"""

new_block = """            .onChange(of: selectedFeature) {
                if let feature = selectedFeature {"""

content = content.replace(old_block, new_block)

with open("InkSlate/Views/Places/PlacesMapView.swift", "w") as f:
    f.write(content)
print("Patched onChange to 0 arguments successfully.")
