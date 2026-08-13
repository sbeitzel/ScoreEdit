import SwiftUI

public struct ContentView: View {
    @Binding var document: ABCDocument

    let fileURL: URL?
    var directory: URL? { fileURL?.deletingLastPathComponent() }

    @State private var includeAccess = IncludeFileAccessResolver()

    @State private var editorScrollProportion: Double = 0
    @State private var editorContentHeight: Double = 0
    @State private var editorVisibleHeight: Double = 0

    @State private var previewScrollProportion: Double = 0
    @State private var previewContentHeight: Double = 0
    @State private var previewVisibleHeight: Double = 0

    @State private var scrollAnchors: [(abcLine: Int, svgY: Double)] = []

    @State private var diagnostics: [EditorDiagnostic] = []
    @State private var includeDirectives: [IncludeDirective] = []

    public var body: some View {
        HSplitView {
            ABCEditorView(
                text: $document.text,
                scrollProportion: editorScrollProportion,
                onScrollProportionChanged: { proportion in
                    editorScrollProportion = proportion
                    previewScrollProportion = interpolateScrollProportion(
                        sourceProportion: proportion,
                        anchors: scrollAnchors,
                        editorContentHeight: editorContentHeight,
                        previewContentHeight: previewContentHeight,
                        direction: .editorToPreview
                    )
                },
                contentHeight: $editorContentHeight,
                visibleHeight: $editorVisibleHeight
            )
            .frame(minWidth: 200)
            ScorePreviewView(
                abcText: document.text,
                baseDir: directory,
                includeAccess: includeAccess,
                scrollAnchors: $scrollAnchors,
                diagnostics: $diagnostics,
                scrollProportion: previewScrollProportion,
                onScrollProportionChanged: { proportion in
                    previewScrollProportion = proportion
                    editorScrollProportion = interpolateScrollProportion(
                        sourceProportion: proportion,
                        anchors: scrollAnchors,
                        editorContentHeight: editorContentHeight,
                        previewContentHeight: previewContentHeight,
                        direction: .previewToEditor
                    )
                },
                contentHeight: $previewContentHeight,
                visibleHeight: $previewVisibleHeight
            )
            .frame(minWidth: 200)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            includeDirectives = IncludeDirectiveScanner.scan(document.text)
        }
        .onChange(of: document.text) { _, newText in
            includeDirectives = IncludeDirectiveScanner.scan(newText)
        }
    }
}

#Preview {
    ContentView(document: .constant(ABCDocument()), fileURL: nil)
}
