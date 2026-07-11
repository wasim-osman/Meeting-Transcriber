import SwiftUI

@main
struct MeetingTranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .navigationTitle("Media Summarizer")
                    .navigationSubtitle("By Wasim Osman")
            }
            .frame(minWidth: 820, minHeight: 700)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1020, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
