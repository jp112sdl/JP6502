import SwiftUI

@main
struct JP6502ControlApp: App {
    @State private var settings = AppSettings.shared
    @State private var index = ProjectIndex(settings: AppSettings.shared)

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings, index: index)
                .frame(minWidth: 720, minHeight: 560)
        }
        .defaultSize(width: 940, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan the project") { index.reload() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
