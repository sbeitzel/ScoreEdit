import SwiftUI

public struct ContentView: View {
    @Binding var document: ABCDocument

    let fileURL: URL?
    var directory: URL? { fileURL?.deletingLastPathComponent() }

    @State private var includeAccess = IncludeFileAccessResolver()

    public var body: some View {
        HSplitView {
            TextEditor(text: $document.text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 200)
            ScorePreviewView(abcText: document.text, baseDir: directory, includeAccess: includeAccess)
                .frame(minWidth: 200)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView(document: .constant(ABCDocument()), fileURL: nil)
}
