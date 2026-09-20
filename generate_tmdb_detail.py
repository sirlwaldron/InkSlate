import re

with open("InkSlate/Views/WantToWatch/WantToWatchViews.swift", "r") as f:
    content = f.read()

match = re.search(r'(// MARK: - Item Detail View\nstruct ItemDetailView: View \{.*?\n\})', content, re.DOTALL)
if match:
    detail_view = match.group(1)
    
    # Replace struct name
    detail_view = detail_view.replace("struct ItemDetailView: View", "struct TMDBItemDetailView: View")
    
    # Replace item type
    detail_view = detail_view.replace("@ObservedObject var item: WantToWatchItem", "let item: TMDBItem\n    let onAdd: () -> Void\n    @State private var isAdded = false")
    
    # Remove context
    detail_view = re.sub(r'\s*@Environment\(\\\.managedObjectContext\).*?\n', '\n', detail_view)
    
    # Replace title
    detail_view = detail_view.replace("item.title ?? \"Unknown\"", "item.displayTitle")
    
    # Replace date formatting
    detail_view = detail_view.replace("if let releaseDate = item.releaseDate {", "if let displayDate = item.displayDate {")
    detail_view = detail_view.replace("Text(formatYear(releaseDate))", "Text(String(displayDate.prefix(4)))")
    
    # Replace loadFullDetails
    detail_view = detail_view.replace("Int(item.tmdbId)", "item.id")
    
    # Replace watched button
    button_match = re.search(r'(\s*// Primary watched action — no competing gestures.*?)\n\s*if let cast', detail_view, re.DOTALL)
    if button_match:
        old_button = button_match.group(1)
        new_button = """
                    // Add to list action
                    Button(action: {
                        guard !isAdded else { return }
                        onAdd()
                        withAnimation(.spring()) { isAdded = true }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text(isAdded ? "Added to Watchlist" : "Add to Watchlist")
                                .font(DesignSystem.Typography.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isAdded ? DesignSystem.Colors.success : DesignSystem.Colors.info)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .disabled(isAdded)
"""
        detail_view = detail_view.replace(old_button, new_button)
        
    # Remove toggleWatchedStatus method
    detail_view = re.sub(r'\s*private func toggleWatchedStatus\(\) \{.*?\}\n', '\n', detail_view, flags=re.DOTALL)
    
    with open("TMDBItemDetailView.swift.snippet", "w") as f:
        f.write(detail_view)
    print("Success")
else:
    print("Could not find ItemDetailView")
