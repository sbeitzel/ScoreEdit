import CoreGraphics

/// Geometry of the preview's document view: the displayed size of every page
/// and the overall document size they add up to (#39).
///
/// Computing this explicitly — rather than letting Auto Layout derive it from
/// the hosted SwiftUI content — keeps the document exactly as tall as its
/// pages at any width, and lets it grow wider than the viewport so the scroll
/// view can scroll horizontally.
struct PreviewLayout: Equatable {
    /// Inset around the column of pages.
    static let padding: Double = 16
    /// Vertical gap between consecutive pages.
    static let spacing: Double = 12
    /// Page size assumed for an SVG whose dimensions can't be read (US Letter).
    static let fallbackPageSize = CGSize(width: 612, height: 792)

    /// Displayed size of each page, in points.
    let pageSizes: [CGSize]
    /// Size of the whole document view, in points.
    let documentSize: CGSize

    /// - Parameters:
    ///   - naturalPageSizes: Each page's size in SVG user units.
    ///   - scale: Points per SVG unit, or `nil` to fit each page to the
    ///     viewport width.
    ///   - viewportWidth: Width of the scroll view's visible area.
    init(naturalPageSizes: [CGSize], scale: Double?, viewportWidth: Double) {
        let available = Self.availableWidth(viewportWidth: viewportWidth)
        pageSizes = naturalPageSizes.map { natural in
            guard natural.width > 0, natural.height > 0 else { return .zero }
            let pageScale = scale ?? (available / natural.width)
            return CGSize(width: natural.width * pageScale, height: natural.height * pageScale)
        }

        let widestPage = pageSizes.map(\.width).max() ?? 0
        let width = max(viewportWidth, widestPage + 2 * Self.padding)
        let height: Double
        if pageSizes.isEmpty {
            height = 0
        } else {
            height = pageSizes.reduce(2 * Self.padding) { $0 + $1.height }
                + Self.spacing * Double(pageSizes.count - 1)
        }
        documentSize = CGSize(width: width, height: height)
    }

    /// The scale at which the widest page exactly fills the viewport width, or
    /// `nil` if there are no measurable pages.
    static func fitScale(naturalPageSizes: [CGSize], viewportWidth: Double) -> Double? {
        guard let widest = naturalPageSizes.map(\.width).max(), widest > 0 else { return nil }
        return availableWidth(viewportWidth: viewportWidth) / widest
    }

    /// Each page's size in SVG user units, falling back to US Letter.
    static func naturalPageSizes(of pages: [String]) -> [CGSize] {
        pages.map { svg in
            guard let size = SVGPageView.svgSize(svg), size.width > 0, size.height > 0 else {
                return fallbackPageSize
            }
            return CGSize(width: size.width, height: size.height)
        }
    }

    private static func availableWidth(viewportWidth: Double) -> Double {
        max(viewportWidth - 2 * padding, 1)
    }
}
