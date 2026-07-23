import SwiftUI
import CeolKitModel
import CeolKitParser
import CeolKitSVGRenderer
import Logging

struct ScorePreviewView: View {
    let abcText: String
    let baseDir: URL?
    let includeAccess: IncludeFileAccessResolver
    @Binding var scrollAnchors: [(abcLine: Int, svgY: Double)]
    var scrollProportion: Double
    var onScrollProportionChanged: (Double) -> Void
    @Binding var contentHeight: Double
    @Binding var visibleHeight: Double
    let logger: Logger = Logger(label: "ScorePreviewView")

    @State private var svgPages: [String] = []
    @State private var renderError: String?
    @State private var renderTask: Task<Void, Never>?
    @State private var pendingIncludeURLs: Set<URL> = []

    var body: some View {
        VStack(spacing: 0) {
            if !pendingIncludeURLs.isEmpty {
                includeAccessBanner
            }
            Group {
                if let renderError {
                    ScrollView {
                        Text(renderError)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if svgPages.isEmpty {
                    Text(.klabelScorePreview)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollablePreviewHost(
                        pages: svgPages,
                        scrollProportion: scrollProportion,
                        onScrollProportionChanged: onScrollProportionChanged,
                        contentHeight: $contentHeight,
                        visibleHeight: $visibleHeight
                    )
                }
            }
        }
        .onAppear {
            logger.trace("[ScorePreview] onAppear — text length: \(abcText.count)")
            scheduleRender()
        }
        .onChange(of: abcText) { _, new in
            logger.trace("[ScorePreview] onChange — new text length: \(new.count)")
            scheduleRender()
        }
    }

    private var includeAccessBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(pendingIncludeURLs).sorted { $0.path < $1.path }, id: \.self) { url in
                HStack {
                    Text(.kerrFileAccess(name: url.lastPathComponent))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(.kbuttonGrantAccess) {
                        if includeAccess.grantAccess(to: url) {
                            scheduleRender()
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.15))
    }

    private func scheduleRender() {
        renderTask?.cancel()
        let workingDirectory = baseDir
        let resolver = includeAccess
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                logger.trace("[ScorePreview] render task cancelled before start")
                return
            }
            let text = abcText
            logger.trace("launching renderABC, text length: \(text.count)")
            let (pages, err) = await Task.detached(priority: .userInitiated) {
                renderABC(text, baseDir: workingDirectory, fileResolver: resolver.resolve)
            }.value
            guard !Task.isCancelled else {
                logger.trace("render task cancelled after renderABC returned")
                return
            }
            logger.info("renderABC finished — pages: \(pages.count), error: \(err ?? "none")")
            svgPages = pages
            scrollAnchors = Self.scrollAnchors(forPages: pages)
            renderError = err
            pendingIncludeURLs = resolver.pendingURLs
        }
    }

    /// Extracts the `ceolkit-meta` anchor comment (CeolKit#25) from each page and
    /// builds a document-absolute anchor table by offsetting each page's anchors
    /// by the accumulated height of all preceding pages.
    nonisolated static func scrollAnchors(forPages pages: [String]) -> [(abcLine: Int, svgY: Double)] {
        var result: [(abcLine: Int, svgY: Double)] = []
        var offset: Double = 0
        for svg in pages {
            for anchor in pageAnchors(svg) {
                result.append((abcLine: anchor.abcLine, svgY: anchor.y + offset))
            }
            offset += SVGPageView.svgSize(svg)?.height ?? PageSize.letter.height
        }
        return result.sorted { $0.abcLine < $1.abcLine }
    }

    private nonisolated static func pageAnchors(_ svg: String) -> [PageAnchor] {
        guard let match = try? /<!--\s*ceolkit-meta:\s*(\{.*?\})\s*-->/.firstMatch(in: svg),
              let data = String(match.1).data(using: .utf8),
              let meta = try? JSONDecoder().decode(PageMeta.self, from: data) else {
            return []
        }
        return meta.anchors
    }
}

private struct PageMeta: Decodable {
    let page: Int
    let anchors: [PageAnchor]
}

private struct PageAnchor: Decodable {
    let abcLine: Int
    let y: Double
}

private func renderABC(
    _ text: String,
    baseDir: URL? = nil,
    fileResolver: CeolKitParser.FileResolver? = nil
) -> (pages: [String], error: String?) {
    let log: Logger = Logger(label: "renderABC")
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        log.info("empty input, skipping")
        return ([], nil)
    }

    log.trace("parsing \(trimmed.count) chars")
    let parser = CeolKitParser(for: baseDir, fileResolver: fileResolver)
    let result = parser.parse(trimmed, options: .default)

    log.trace("parse complete — tunes: \(result.score.tunes.count), diagnostics: \(result.diagnostics.count)")
    for diag in result.diagnostics {
        log.info("diag [\(diag.severity)]: \(diag.message)")
    }
    for (ti, tune) in result.score.tunes.enumerated() {
        log.trace("tune[\(ti)]: voices=\(tune.voices.count)")
        for (vi, voice) in tune.voices.enumerated() {
            let measureCount = voice.staves.flatMap { $0.measures }.count
            log.trace(" voice[\(vi)]: staves=\(voice.staves.count), measures=\(measureCount)")
        }
    }

    let renderer = SVGRenderer(config: SVGRenderConfig(pageSize: .letter))
    do {
        let pages = try renderer.render(result.score)
        log.info("renderer produced \(pages.count) page(s)")
        for (i, svg) in pages.enumerated() {
            log.trace("page[\(i)]: \(svg.count) chars, prefix: \(svg.prefix(120))")
        }
        return (pages, nil)
    } catch {
        log.warning("renderer threw: \(error)")
        return ([], error.localizedDescription)
    }
}

#Preview {
    // Previews run outside ScoreEditApp.init(), so register the fonts here too.
    let _ = CeolKitFonts.register()
    let kalabakan = """
        %abc-2.2
        %%ceolkit:pipeformat true
        %%ceolkit:justifylast true
        %%titleformat T0, R-1 C1
        %%writefields TRCQ true
        %%footer "\t\tGenerated: $D"
        %%straightflags false
        %%graceslurs false
        %%dateformat "%e %B %Y %H:%M"
        %%landscape 1
        X:1
        T:Kalabakan (Borneo)
        R:Reel
        C:P/M A. MacDonald
        Z:abc-transcription Stephen Beitzel, <sbeitzel@pobox.com>, 2025-11-16
        M:C|
        L:1/8
        Q: 1/4 = 78
        K:D
        [|: A/ | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 :|]
        [| f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}f>e {Gdc}d2 {g}d>f |
        {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
        [| A/ | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d>A |
        {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
        [| a/ | {fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>e{A}e>f {gef}e2 {ag}a2 |
        {fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 z |]
        """
    ScorePreviewView(
        abcText: kalabakan,
        baseDir: nil,
        includeAccess: IncludeFileAccessResolver(),
        scrollAnchors: .constant([]),
        scrollProportion: 0,
        onScrollProportionChanged: { _ in },
        contentHeight: .constant(0),
        visibleHeight: .constant(0)
    )
}
