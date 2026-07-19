import SwiftUI

@main
struct MeetingTranscriberApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(state: state)
                    .navigationTitle("Meeting Transcriber")
                    .navigationSubtitle("By HarmlessParasite")
            }
            .frame(minWidth: 820, minHeight: 700)
        .task {
            Task { @MainActor in
                state.refreshSummarizationAvailability()
            }
        }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1020, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
