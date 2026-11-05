import SwiftUI

@main
struct SpacectlUIApp: App {
    private let model = StacksViewModel()

    var body: some Scene {
        WindowGroup("Spacelift Stacks") {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Command Palette…") { model.togglePalette() }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
