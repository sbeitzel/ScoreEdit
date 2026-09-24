import SwiftUI

/// Zoom level of the score preview (#38): either fit each page to the pane
/// width, or a fixed percentage of the page's natural size.
///
/// Raw value is the percentage, with 0 meaning fit width, so it can be kept in
/// `@SceneStorage`.
enum PreviewZoom: Hashable, RawRepresentable {
    case fitWidth
    case percent(Int)

    static let presets = [50, 75, 100, 125, 150, 200, 300, 400]
    static let actualSize = PreviewZoom.percent(100)

    init(rawValue: Int) {
        self = rawValue > 0 ? .percent(rawValue) : .fitWidth
    }

    var rawValue: Int {
        switch self {
        case .fitWidth: 0
        case .percent(let percent): percent
        }
    }

    /// Points per SVG unit, or `nil` for fit width.
    var scale: Double? {
        switch self {
        case .fitWidth: nil
        case .percent(let percent): Double(percent) / 100
        }
    }

    /// The next preset larger than the current effective zoom, or `nil` if
    /// already at or past the largest. `fitScale` is the scale fit width
    /// currently resolves to.
    func zoomedIn(fitScale: Double?) -> PreviewZoom? {
        let current = effectivePercent(fitScale: fitScale)
        return Self.presets.first { Double($0) > current + Self.tolerance }.map(PreviewZoom.percent)
    }

    /// The next preset smaller than the current effective zoom, or `nil` if
    /// already at or below the smallest.
    func zoomedOut(fitScale: Double?) -> PreviewZoom? {
        let current = effectivePercent(fitScale: fitScale)
        return Self.presets.last { Double($0) < current - Self.tolerance }.map(PreviewZoom.percent)
    }

    /// Treat a fit scale within half a percent of a preset as that preset, so
    /// stepping from fit width never lands on a visually identical level.
    private static let tolerance = 0.5

    private func effectivePercent(fitScale: Double?) -> Double {
        switch self {
        case .fitWidth: (fitScale ?? 1) * 100
        case .percent(let percent): Double(percent)
        }
    }
}

/// The focused window's preview zoom, exposed to the View menu commands.
struct PreviewZoomControl {
    @Binding var zoom: PreviewZoom
    var fitScale: Double?

    var zoomIn: PreviewZoom? { zoom.zoomedIn(fitScale: fitScale) }
    var zoomOut: PreviewZoom? { zoom.zoomedOut(fitScale: fitScale) }
}

extension FocusedValues {
    @Entry var previewZoom: PreviewZoomControl?
}

/// View menu items for zooming the focused window's preview.
struct PreviewZoomCommands: Commands {
    @FocusedValue(\.previewZoom) private var control

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(.kbuttonZoomIn) {
                if let next = control?.zoomIn { control?.zoom = next }
            }
            .keyboardShortcut("+")
            .disabled(control?.zoomIn == nil)

            Button(.kbuttonZoomOut) {
                if let next = control?.zoomOut { control?.zoom = next }
            }
            .keyboardShortcut("-")
            .disabled(control?.zoomOut == nil)

            Button(.kbuttonActualSize) {
                control?.zoom = .actualSize
            }
            .keyboardShortcut("0")
            .disabled(control == nil || control?.zoom == .actualSize)

            Button(.kbuttonFitWidth) {
                control?.zoom = .fitWidth
            }
            .disabled(control == nil || control?.zoom == .fitWidth)

            Divider()
        }
    }
}

/// Zoom out / level picker / zoom in, overlaid on the preview pane.
struct PreviewZoomControlView: View {
    @Binding var zoom: PreviewZoom
    var fitScale: Double?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if let next = zoom.zoomedOut(fitScale: fitScale) { zoom = next }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help(Text(.kbuttonZoomOut))
            .accessibilityLabel(Text(.kbuttonZoomOut))
            .disabled(zoom.zoomedOut(fitScale: fitScale) == nil)

            Picker(selection: $zoom) {
                Text(.kbuttonFitWidth).tag(PreviewZoom.fitWidth)
                Divider()
                ForEach(PreviewZoom.presets, id: \.self) { percent in
                    Text(Double(percent) / 100, format: .percent).tag(PreviewZoom.percent(percent))
                }
            } label: {
                Text(.klabelZoom)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Button {
                if let next = zoom.zoomedIn(fitScale: fitScale) { zoom = next }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help(Text(.kbuttonZoomIn))
            .accessibilityLabel(Text(.kbuttonZoomIn))
            .disabled(zoom.zoomedIn(fitScale: fitScale) == nil)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}
