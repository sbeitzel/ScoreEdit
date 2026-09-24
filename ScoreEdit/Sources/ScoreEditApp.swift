import Logging
import Sparkle
import SwiftUI

@main
struct ScoreEditApp: App {
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
          CommandGroup(after: .appInfo) {
              Button(.kbuttonCheckUpdates) {
              updaterController.updater.checkForUpdates()
            }
          }
          PreviewZoomCommands()
        }
    }
}
