import re

with open("InkSlate/Core/ContentView.swift", "r") as f:
    content = f.read()

# For macBody
old_mac = """            onProChange: { isPro in
                // Auto-dismiss removed so users can see the success message
            },"""

new_mac = """            onProChange: { isPro in
                if isPro {
                    if case .paywall(let feature) = activeFullScreenCover, let f = feature {
                        applyMenuSelection(f)
                    }
                }
            },"""

content = content.replace(old_mac, new_mac)

with open("InkSlate/Core/ContentView.swift", "w") as f:
    f.write(content)

print("Patched ContentView successfully.")
