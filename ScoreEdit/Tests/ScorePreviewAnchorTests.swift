import Testing
@testable import ScoreEdit

struct ScorePreviewAnchorTests {

    private func svg(page: Int, anchors: [(abcLine: Int, y: Double)], width: Double = 612, height: Double = 792) -> String {
        let anchorJSON = anchors
            .map { "{\"abcLine\": \($0.abcLine), \"y\": \($0.y)}" }
            .joined(separator: ", ")
        return """
        <svg width="\(width)" height="\(height)">
        <!-- ceolkit-meta: {"page": \(page), "anchors": [\(anchorJSON)]} -->
        </svg>
        """
    }

    @Test func singlePageAnchorsAreUnchanged() {
        let page = svg(page: 1, anchors: [(1, 0.0), (15, 142.5)])
        let result = ScorePreviewView.scrollAnchors(forPages: [page])
        #expect(result.map(\.abcLine) == [1, 15])
        #expect(result.map(\.svgY) == [0.0, 142.5])
    }

    @Test func secondPageAnchorsAreOffsetByFirstPageHeight() {
        let page1 = svg(page: 1, anchors: [(1, 0.0), (15, 142.5)], height: 792)
        let page2 = svg(page: 2, anchors: [(31, 20.0)], height: 792)
        let result = ScorePreviewView.scrollAnchors(forPages: [page1, page2])
        #expect(result.map(\.abcLine) == [1, 15, 31])
        #expect(result.map(\.svgY) == [0.0, 142.5, 812.0])
    }

    @Test func resultIsSortedByAbcLineEvenIfPagesAreOutOfOrder() {
        let page1 = svg(page: 1, anchors: [(31, 5.0)], height: 792)
        let page2 = svg(page: 2, anchors: [(1, 0.0)], height: 792)
        let result = ScorePreviewView.scrollAnchors(forPages: [page1, page2])
        #expect(result.map(\.abcLine) == [1, 31])
    }

    @Test func pageWithoutMetadataCommentContributesNoAnchors() {
        let noMeta = "<svg width=\"612\" height=\"792\"></svg>"
        let withMeta = svg(page: 2, anchors: [(10, 5.0)], height: 792)
        let result = ScorePreviewView.scrollAnchors(forPages: [noMeta, withMeta])
        #expect(result.map(\.abcLine) == [10])
        #expect(result.map(\.svgY) == [797.0])
    }

    @Test func emptyPagesProduceEmptyAnchorTable() {
        let result = ScorePreviewView.scrollAnchors(forPages: [])
        #expect(result.isEmpty)
    }
}
