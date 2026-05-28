import ProjectDescription

let project = Project(
    name: "ScoreEdit",
    targets: [
        .target(
            name: "ScoreEdit",
            destinations: .macOS,
            product: .app,
            bundleId: "com.qbcps.ScoreEdit",
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "NSHighResolutionCapable": true,
                "NSPrincipalClass": "NSApplication",
                "CFBundleDocumentTypes": [
                    [
                        "CFBundleTypeName": "ABC Notation",
                        "CFBundleTypeRole": "Editor",
                        "LSHandlerRank": "Owner",
                        "LSItemContentTypes": ["com.qbcps.abc-notation"],
                        "CFBundleTypeExtensions": ["abc"],
                        "CFBundleTypeMIMETypes": ["text/vnd.abc"],
                    ]
                ],
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.qbcps.abc-notation",
                        "UTTypeDescription": "ABC Notation",
                        "UTTypeConformsTo": ["public.plain-text"],
                        "UTTypeTagSpecification": [
                            "public.filename-extension": ["abc"],
                            "public.mime-type": ["text/vnd.abc"],
                        ],
                    ]
                ],
            ]),
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
