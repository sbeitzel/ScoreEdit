import AppKit
import Logging
import SwiftUI
import SVGKit

struct SVGPageView: NSViewRepresentable {
    let svgString: String
    /// Displayed size of the page. SVGKit draws at the image's own size rather
    /// than scaling to the view's frame, so the image is resized to match
    /// (#38); CeolKit's pages carry a `viewBox`, so this scales the drawing.
    var size: CGSize = .zero
    let log: Logger = Logger(label: "ScoreEdit.SVGPageView")

    func makeNSView(context: Context) -> SVGKLayeredImageView {
        log.trace("makeNSView — svgString length: \(svgString.count)")
        let image = makeImage()
        Self.applySize(size, to: image)
        let coordinator = context.coordinator
        coordinator.svgString = svgString
        coordinator.size = size
        return SVGKLayeredImageView(svgkImage: image)
    }

    func updateNSView(_ nsView: SVGKLayeredImageView, context: Context) {
        let coordinator = context.coordinator
        if svgString != coordinator.svgString {
            log.trace("updateNSView — new svgString length: \(svgString.count)")
            let image = makeImage()
            Self.applySize(size, to: image)
            nsView.image = image
        } else if size != coordinator.size {
            log.trace("updateNSView — resize to \(size)")
            Self.resize(nsView, to: size)
        } else {
            return
        }
        coordinator.svgString = svgString
        coordinator.size = size
    }

    /// Claim exactly the page size. Left to its default, SwiftUI keeps the
    /// AppKit view's earlier size after a zoom change, and the stale-sized page
    /// is centered — i.e. offset — in its smaller frame.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SVGKLayeredImageView, context: Context) -> CGSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// What the view was last configured with, so an unrelated SwiftUI update
    /// doesn't re-parse or re-lay out the SVG.
    final class Coordinator {
        var svgString: String?
        var size: CGSize = .zero
    }

    /// Redraws the view's current image at a new size without re-parsing it.
    ///
    /// `SVGKLayer` ignores being handed the image it already shows, and setting
    /// `SVGKImage.size` discards the image's cached layer tree — after which the
    /// layer can no longer find the old tree to remove it. So detach the image
    /// while its tree is still the one on screen, resize, then reattach so the
    /// layer adds the freshly built tree.
    static func resize(_ view: SVGKLayeredImageView, to size: CGSize) {
        guard let image = view.image else { return }
        view.image = nil
        applySize(size, to: image)
        view.image = image
    }

    private static func applySize(_ size: CGSize, to image: SVGKImage) {
        guard size.width > 0, size.height > 0 else { return }
        image.size = size
    }

    private func makeImage() -> SVGKImage {
        let source = SVGKSourceString.source(fromContentsOf: svgString)
        let image = SVGKImage(source: source)
        if let image {
            log.trace("SVGKImage created — size: \(image.size)")
        } else {
            log.trace("SVGKImage(source:) returned nil, falling back to empty SVGKImage")
        }
        return image ?? SVGKImage()
    }
}

extension SVGPageView {
    /// The page's size in SVG user units: the `viewBox` extent if present (the
    /// units scroll anchors are in), otherwise `width`/`height`, which CeolKit
    /// writes with a `pt` unit.
    nonisolated static func svgSize(_ svg: String) -> (width: Double, height: Double)? {
        if let m = try? /viewBox="\s*[-\d.]+[\s,]+[-\d.]+[\s,]+([\d.]+)[\s,]+([\d.]+)\s*"/.firstMatch(in: svg),
           let w = Double(m.1), let h = Double(m.2) {
            return (w, h)
        }
        guard let m = try? /width="([\d.]+)(?:pt|px)?"\s+height="([\d.]+)(?:pt|px)?"/.firstMatch(in: svg),
              let w = Double(m.1), let h = Double(m.2) else { return nil }
        return (w, h)
    }

    nonisolated static func aspectRatio(_ svg: String) -> Double? {
        guard let size = svgSize(svg), size.height > 0 else { return nil }
        return size.width / size.height
    }
}
