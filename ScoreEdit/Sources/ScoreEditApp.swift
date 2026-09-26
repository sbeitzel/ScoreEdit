import Logging
import Sparkle
import SwiftUI

@main
struct ScoreEditApp: App {
    @Environment(\.openWindow) private var openWindow

    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        // Bootstrap the logging system to go to the console
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput(label:))
    }

    var body: some Scene {
        DocumentGroup(newDocument: ABCDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    openWindow(id: .kWID_about)
                } label: {
                    Text(.kmenuAbout)
                }
            }

            CommandGroup(after: .appInfo) {
                Button(.kbuttonCheckUpdates) {
                    updaterController.updater.checkForUpdates()
                }
            }
            PreviewZoomCommands()
        }

        Window(.kwindowAbout, id: .kWID_about) {
            AboutView()
                .containerBackground(.regularMaterial, for: .window)
                .toolbar(removing: .title)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .windowMinimizeBehavior(.disabled)
        }
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window(.kwindowCredits, id: .kWID_credits) {
            CreditsView()
                .windowMinimizeBehavior(.disabled)
        }
        .windowResizability(.automatic)
        .restorationBehavior(.disabled)

    }
}
