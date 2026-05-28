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
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/sbeitzel/SVGKit", branch: "macOS"),
        .package(url: "https://github.com/sbeitzel/CeolKit", branch: "main"),
        // Pin transitive deps to versions that predate enableUpcomingFeature,
        // which Tuist cannot parse in SPM package manifests.
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", .upToNextMinor(from: "3.8.0")),
        .package(url: "https://github.com/apple/swift-log", .upToNextMinor(from: "1.5.0")),
    ]
)
