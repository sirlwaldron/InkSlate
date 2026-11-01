import SwiftUI

extension Notification.Name {
    static let inkSlateNewNote = Notification.Name("InkSlateNewNote")
    static let inkSlateSearchNotes = Notification.Name("InkSlateSearchNotes")
    static let inkSlateSave = Notification.Name("InkSlateSave")
    static let inkSlateToggleSidebar = Notification.Name("InkSlateToggleSidebar")
    static let inkSlateOpenSettings = Notification.Name("InkSlateOpenSettings")
}

#if os(macOS)
struct InkSlateCommands: Commands {
    @FocusedValue(\.inkSlateCommandContext) private var commandContext

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                commandContext?.newNote()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Edit") {
            Button("Save") {
                commandContext?.save()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Search Notes") {
                commandContext?.searchNotes()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button("Home") { commandContext?.selectMenu(.items) }
                .keyboardShortcut("1", modifiers: .command)
            Button("To-Do") { commandContext?.selectMenu(.todo) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Notes") { commandContext?.selectMenu(.notes) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Recipes") { commandContext?.selectMenu(.recipes) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Places") { commandContext?.selectMenu(.places) }
                .keyboardShortcut("5", modifiers: .command)
            Button("Watchlist") { commandContext?.selectMenu(.wantToWatch) }
                .keyboardShortcut("6", modifiers: .command)
            Button("Mind Maps") { commandContext?.selectMenu(.mindMaps) }
                .keyboardShortcut("7", modifiers: .command)
            Button("Journal") { commandContext?.selectMenu(.journal) }
                .keyboardShortcut("8", modifiers: .command)
            Button("Budget") { commandContext?.selectMenu(.budget) }
                .keyboardShortcut("9", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                commandContext?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                commandContext?.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

struct InkSlateCommandContext {
    var newNote: () -> Void = {}
    var save: () -> Void = {}
    var searchNotes: () -> Void = {}
    var toggleSidebar: () -> Void = {}
    var openSettings: () -> Void = {}
    var selectMenu: (MenuViewType) -> Void = { _ in }
}

private struct InkSlateCommandContextKey: FocusedValueKey {
    typealias Value = InkSlateCommandContext
}

extension FocusedValues {
    var inkSlateCommandContext: InkSlateCommandContext? {
        get { self[InkSlateCommandContextKey.self] }
        set { self[InkSlateCommandContextKey.self] = newValue }
    }
}

#endif
