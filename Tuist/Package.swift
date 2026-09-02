// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [:],
        targetSettings: [
            // CocoaLumberjack's "+Deprecated.m" category files add no new symbols,
            // which makes libtool emit a harmless "has no symbols" warning when it
            // archives the static library. Silence it at the source.
            "CocoaLumberjack": .settings(base: ["OTHER_LIBTOOLFLAGS": "-no_warning_for_no_symbols"]),
            // Same story for a few of SVGKit's category-only / platform-gated files
            // (SVGKExporterUIImage.m compiles to nothing on macOS, etc).
            "SVGKit": .settings(base: ["OTHER_LIBTOOLFLAGS": "-no_warning_for_no_symbols"]),
        ]
    )
#endif

let package = Package(
    name: "ScoreEdit",
    dependencies: [
        .package(url: "https://github.com/SVGKit/SVGKit", branch: "3.x"), // for rendering previews
        .package(url: "https://github.com/sbeitzel/CeolKit", from: "1.3.0"), // use for releases
//        .package(path: "../../CeolKit"), // local development
        // TODO: evaluate this for truth, as some time has passed since I started this project
        // Pin transitive deps to versions that predate enableUpcomingFeature,
        // which Tuist cannot parse in SPM package manifests.
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", .upToNextMinor(from: "3.8.0")),
        .package(url: "https://github.com/apple/swift-log", from: "1.14.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        // Transitive dep from CeolKit's test target — must be declared so Tuist can resolve the graph.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ]
)
