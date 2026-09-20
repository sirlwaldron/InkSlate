import re

with open("InkSlate/Views/Places/PlacesViews.swift", "r") as f:
    content = f.read()

# Replace getOrCreateUncategorizedPlaceCategory
old1 = "fileprivate func getOrCreateUncategorizedPlaceCategory(for type: PlaceType, context: NSManagedObjectContext) -> PlaceCategory {"
new1 = "@MainActor\nfileprivate func getOrCreateUncategorizedPlaceCategory(for type: PlaceType, context: NSManagedObjectContext) -> PlaceCategory {"
content = content.replace(old1, new1)

# Replace mergeDuplicateUncategorizedCategories
old2 = """fileprivate func mergeDuplicateUncategorizedCategories(
    keeper: PlaceCategory,
    duplicates: [PlaceCategory],
    context: NSManagedObjectContext
) {"""
new2 = """@MainActor
fileprivate func mergeDuplicateUncategorizedCategories(
    keeper: PlaceCategory,
    duplicates: [PlaceCategory],
    context: NSManagedObjectContext
) {"""
content = content.replace(old2, new2)

# Replace deduplicateUncategorizedPlaceCategories
old3 = "fileprivate func deduplicateUncategorizedPlaceCategories(in context: NSManagedObjectContext) {"
new3 = "@MainActor\nfileprivate func deduplicateUncategorizedPlaceCategories(in context: NSManagedObjectContext) {"
content = content.replace(old3, new3)

with open("InkSlate/Views/Places/PlacesViews.swift", "w") as f:
    f.write(content)

print("Patched successfully.")
