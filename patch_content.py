import re

with open("InkSlate/Core/ContentView.swift", "r") as f:
    content = f.read()

# For macBody
old_mac = """            onProChange: { isPro in
                if isPro {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        activeFullScreenCover = nil
                    }
                }
            },"""

new_mac = """            onProChange: { isPro in
                // Auto-dismiss removed so users can see the success message
            },"""

content = content.replace(old_mac, new_mac)

with open("InkSlate/Core/ContentView.swift", "w") as f:
    f.write(content)

print("Patched ContentView successfully.")
