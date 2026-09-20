import re

with open("InkSlate/Views/Places/PlacesViews.swift", "r") as f:
    content = f.read()

old_block = """private func inferredPlaceType(for category: PlaceCategory) -> PlaceType {
    if let marker = category.icon?.lowercased() {
        if marker.contains("restaurant") || marker.contains("fork") || marker.contains("knife") {
            return .restaurant
        }
        if marker.contains("activity") || marker.contains("figure") || marker.contains("run") || marker.contains("sport") {
            return .activity
        }
        if marker.contains("place") || marker.contains("map") || marker.contains("location") {
            return .place
        }
        if PlaceType.allCases.contains(where: { $0.lowercaseKey == marker }) {
            return PlaceType.allCases.first(where: { $0.lowercaseKey == marker }) ?? .place
        }
    }
    
    if let name = category.name?.lowercased() {
        if name.contains("restaurant") || name.contains("dining") || name.contains("food") || name.contains("cafe") {
            return .restaurant
        }
        if name.contains("activity") || name.contains("park") || name.contains("gym") || name.contains("adventure") || name.contains("event") {
            return .activity
        }
        if name.contains("place") || name.contains("travel") || name.contains("destination") {
            return .place
        }
    }
    
    return .place
}"""

new_block = """private func inferredPlaceType(for category: PlaceCategory) -> PlaceType {
    if let typeString = category.type, let type = PlaceType(rawValue: typeString) {
        return type
    }
    
    if let marker = category.icon?.lowercased() {
        if marker.contains("restaurant") || marker.contains("fork") || marker.contains("knife") {
            return .restaurant
        }
        if marker.contains("activity") || marker.contains("figure") || marker.contains("run") || marker.contains("sport") {
            return .activity
        }
        if marker.contains("place") || marker.contains("map") || marker.contains("location") {
            return .place
        }
    }
    
    if let name = category.name?.lowercased() {
        if name.contains("restaurant") || name.contains("dining") || name.contains("food") || name.contains("cafe") {
            return .restaurant
        }
        if name.contains("activity") || name.contains("park") || name.contains("gym") || name.contains("adventure") || name.contains("event") {
            return .activity
        }
    }
    
    return .place
}"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open("InkSlate/Views/Places/PlacesViews.swift", "w") as f:
        f.write(content)
    print("Patched successfully.")
else:
    print("Block not found!")
