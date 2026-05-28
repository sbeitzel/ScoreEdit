import ProjectDescription

let project = Project(
    name: "ScoreEdit",
    targets: [
        .target(
            name: "ScoreEdit",
            destinations: .macOS,
            product: .app,
            bundleId: "com.qbcps.ScoreEdit",
            infoPlist: .default,
            buildableFolders: [
                "ScoreEdit/Sources",
                "ScoreEdit/Resources",
            ],
            dependencies: [
                .external(name: "CeolKitParser"),
                .external(name: "CeolKitSVGRenderer"),
                .external(name: "SVGKitSwift"),
            ]
        ),
        .target(
            name: "ScoreEditTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.qbcps.ScoreEditTests",
            infoPlist: .default,
            buildableFolders: [
                "ScoreEdit/Tests"
            ],
            dependencies: [.target(name: "ScoreEdit")]
        ),
    ]
)
