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
