import re

with open("InkSlate/Views/Places/PlacesViews.swift", "r") as f:
    content = f.read()

old_block = """        do {
            try viewContext.saveWithCloudKitSync()
            dismiss()
        } catch {
            placesLog.error("Quick add place save failed: \\(error.localizedDescription)")
        }"""

new_block = """        if viewContext.inkSlateSave(module: "Places") {
            dismiss()
        } else {
            placesLog.error("Quick add place save failed")
        }"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open("InkSlate/Views/Places/PlacesViews.swift", "w") as f:
        f.write(content)
    print("Patched successfully.")
else:
    print("Block not found!")
