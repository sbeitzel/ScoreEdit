import Logging
import SwiftUI

public struct ContentView: View {
    @Binding var document: ABCDocument
    @Environment(\.openDocument) private var openDocument

    let fileURL: URL?
    var directory: URL? { fileURL?.deletingLastPathComponent() }
    let logger: Logger = Logger(label: "ContentView")

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
    @State private var includeOpenFailure: String?
    @State private var renderTrigger = 0

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
                visibleHeight: $editorVisibleHeight,
                diagnostics: diagnostics,
                includeDirectives: includeDirectives,
                onOpenInclude: { directive in openInclude(directive) }
            )
            .frame(minWidth: 200)
            ScorePreviewView(
                abcText: document.text,
                baseDir: directory,
                includeAccess: includeAccess,
                scrollAnchors: $scrollAnchors,
                diagnostics: $diagnostics,
                renderTrigger: renderTrigger,
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
        .alert(
            Text(.kerrOpenInclude(name: includeOpenFailure ?? "")),
            isPresented: Binding(
                get: { includeOpenFailure != nil },
                set: { if !$0 { includeOpenFailure = nil } }
            )
        ) {
            Button(role: .cancel, action: {}) { Text(.kbuttonOk) }
        }
    }

    /// Opens the file referenced by an `I:abc-include` directive in its own
    /// document window (#15, #20). Establishes sandbox access first: a held
    /// security scope (or plain readability) lets `openDocument` read the
    /// file; otherwise the user is asked to grant access via the panel.
    private func openInclude(_ directive: IncludeDirective) {
        guard let url = IncludeDirectiveScanner.resolvedURL(for: directive, baseDir: directory) else {
            logger.info("no base directory; cannot resolve '\(directive.fileName)'")
            return
        }
        Task { @MainActor in
            if includeAccess.beginPersistentAccess(to: url) != nil
                || FileManager.default.isReadableFile(atPath: url.path) {
                logger.info("opening include '\(url.path)'")
                await openIncludeDocument(at: url)
            } else if includeAccess.grantAccess(to: url) {
                includeAccess.beginPersistentAccess(to: url)
                logger.info("access granted; opening include '\(url.path)'")
                await openIncludeDocument(at: url)
                // Access just appeared; the preview may have a stale
                // "cannot read include" diagnostic.
                renderTrigger += 1
            } else {
                logger.info("access not granted for '\(url.path)'")
            }
        }
    }

    @MainActor
    private func openIncludeDocument(at url: URL) async {
        do {
            try await openDocument(at: url)
        } catch {
            logger.warning("openDocument failed for '\(url.path)': \(error)")
            includeOpenFailure = url.lastPathComponent
        }
    }
}

#Preview {
    ContentView(document: .constant(ABCDocument()), fileURL: nil)
}
