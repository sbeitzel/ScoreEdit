import CeolKitSVGRenderer
import Logging
import SwiftUI

@main
struct ScoreEditApp: App {
    init() {
        // Bootstrap the logging system to go to the console
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput(label:))
        // SVGKit resolves font-family against process-registered fonts, not the
        // SVG's embedded @font-face data, so the bundled fonts must be registered.
        CeolKitFonts.register()
    }

    var body: some Scene {
        DocumentGroup(newDocument: ABCDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
    }
}
