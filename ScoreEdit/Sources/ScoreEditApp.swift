import SwiftUI

@main
struct ScoreEditApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ABCDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
