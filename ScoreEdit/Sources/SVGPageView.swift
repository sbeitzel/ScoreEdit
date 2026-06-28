import AppKit
import Logging
import SwiftUI
import SVGKit

struct SVGPageView: NSViewRepresentable {
    let svgString: String
    let log: Logger = Logger(label: "ScoreEdit.SVGPageView")

    func makeNSView(context: Context) -> SVGKLayeredImageView {
        log.trace("makeNSView — svgString length: \(svgString.count)")
        return SVGKLayeredImageView(svgkImage: makeImage())
    }

    func updateNSView(_ nsView: SVGKLayeredImageView, context: Context) {
        log.trace("updateNSView — svgString length: \(svgString.count)")
        nsView.image = makeImage()
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
