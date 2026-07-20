import Foundation

enum ScrollDirection {
    case editorToPreview
    case previewToEditor
}

/// Maps a scroll proportion in one pane to the corresponding proportion in
/// the other, using the anchor table (see #1) to build a piecewise-linear
/// function rather than assuming a single global proportion.
///
/// Anchors are converted to comparable `(editorProportion, previewProportion)`
/// points before interpolating:
/// - The preview axis uses `svgY / previewContentHeight` directly, since
///   `svgY` is already an absolute, document-wide pixel offset (see #1).
/// - The editor axis has no such absolute pixel value to work with — an
///   `abcLine` is just a source line number, and there's no reliable way to
///   recover the editor's total line count from a content height in points
///   alone (line wrapping, blank lines, etc.). Instead it's normalized
///   against the span of lines the anchor table itself covers, i.e. the
///   first and last anchors define editor proportions 0 and 1.
///
/// `editorContentHeight` and `previewContentHeight` are otherwise used only
/// as layout-readiness guards: a pane reporting a non-positive content
/// height hasn't finished laying out yet, so synchronization falls back to
/// the identity mapping rather than dividing by zero.
///
/// Renderers can produce anchors that are duplicated or out of order — e.g.
/// a system a renderer can't attribute to a real source line falling back
/// to a default `abcLine` (seen in practice: many systems scattered across
/// the whole document all reporting line 1). A repeated or decreasing line
/// number collapses two anchors to the same or a backwards position on the
/// editor axis, which turns one segment of the piecewise function into a
/// near-vertical (or reversed) slope — a tiny change in scroll position
/// then swings the mapped result across most of the other pane. `anchors`
/// is filtered to a strictly increasing subsequence (both axes) before use
/// so every segment has a well-defined, bounded slope.
func interpolateScrollProportion(
    sourceProportion: Double,
    anchors: [(abcLine: Int, svgY: Double)],
    editorContentHeight: Double,
    previewContentHeight: Double,
    direction: ScrollDirection
) -> Double {
    let clampedSource = min(max(sourceProportion, 0), 1)

    let usableAnchors = strictlyIncreasing(anchors)
    guard usableAnchors.count > 1, editorContentHeight > 0, previewContentHeight > 0 else {
        return clampedSource
    }

    let firstLine = Double(usableAnchors[0].abcLine)
    let lastLine = Double(usableAnchors[usableAnchors.count - 1].abcLine)
    let lineSpan = lastLine - firstLine
    guard lineSpan > 0 else {
        return clampedSource
    }

    let points: [(editor: Double, preview: Double)] = usableAnchors.map { anchor in
        let editorProportion = (Double(anchor.abcLine) - firstLine) / lineSpan
        let previewProportion = anchor.svgY / previewContentHeight
        return (editorProportion, previewProportion)
    }

    let result: Double
    switch direction {
    case .editorToPreview:
        result = piecewiseLinear(clampedSource, over: points.map { ($0.editor, $0.preview) })
    case .previewToEditor:
        result = piecewiseLinear(clampedSource, over: points.map { ($0.preview, $0.editor) })
    }
    return min(max(result, 0), 1)
}

/// Piecewise-linear lookup over `points`, which must be sorted ascending by
/// their first (x) element. Positions before the first or after the last
/// point are extrapolated using the slope of the nearest segment.
func piecewiseLinear(_ x: Double, over points: [(Double, Double)]) -> Double {
    guard let first = points.first, let last = points.last else { return x }
    guard points.count > 1 else { return first.1 }

    if x <= first.0 {
        return lerp(x, points[0], points[1])
    }
    if x >= last.0 {
        return lerp(x, points[points.count - 2], points[points.count - 1])
    }
    for i in 0..<(points.count - 1) {
        let p0 = points[i], p1 = points[i + 1]
        if x >= p0.0 && x <= p1.0 {
            return lerp(x, p0, p1)
        }
    }
    return last.1
}

private func lerp(_ x: Double, _ p0: (Double, Double), _ p1: (Double, Double)) -> Double {
    let dx = p1.0 - p0.0
    guard dx != 0 else { return p0.1 }
    let t = (x - p0.0) / dx
    return p0.1 + t * (p1.1 - p0.1)
}

/// Keeps `anchors` (assumed sorted ascending by `abcLine`, per #1) in a
/// single greedy pass: the first anchor, then only anchors whose line and Y
/// both strictly exceed the last kept anchor's. Ties and reversals are
/// dropped rather than averaged, since a reversal usually means the
/// dropped anchor's line number is untrustworthy, not that its neighbor is.
func strictlyIncreasing(_ anchors: [(abcLine: Int, svgY: Double)]) -> [(abcLine: Int, svgY: Double)] {
    var result: [(abcLine: Int, svgY: Double)] = []
    for anchor in anchors {
        if let last = result.last, anchor.abcLine <= last.abcLine || anchor.svgY <= last.svgY {
            continue
        }
        result.append(anchor)
    }
    return result
}
