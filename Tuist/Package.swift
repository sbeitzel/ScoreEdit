// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "ScoreEdit",
    dependencies: [
        .package(url: "https://github.com/SVGKit/SVGKit", branch: "3.x"),
        .package(path: "../../CeolKit"),
        // Pin transitive deps to versions that predate enableUpcomingFeature,
        // which Tuist cannot parse in SPM package manifests.
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", .upToNextMinor(from: "3.8.0")),
        .package(url: "https://github.com/apple/swift-log", from: "1.14.0"),
        // Transitive dep from CeolKit's test target — must be declared so Tuist can resolve the graph.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ]
)
