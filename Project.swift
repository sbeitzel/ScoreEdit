import ProjectDescription

let baseSettings: SettingsDictionary = [
    "BUILD_YEAR": "2026",
    "DEVELOPMENT_TEAM": "D3DPVGA48J",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
    "CODE_SIGN_IDENTITY": "Apple Development",
    "CODE_SIGNING_ALLOWED": "YES",
    "SWIFT_VERSION": "6.2",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
    "OTHER_LDFLAGS": "$(inherited) -ObjC"
]

let appSettings: SettingsDictionary = baseSettings.merging([
    "CODE_SIGN_STYLE": "Automatic",
    "CODE_SIGN_ENTITLEMENTS": "ScoreEdit/Resources/ScoreEdit.entitlements",
    "ENABLE_APP_SANDBOX": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_INCOMING_NETWORK_CONNECTIONS": "NO",
    "ENABLE_OUTGOING_NETWORK_CONNECTIONS": "YES",
    "ENABLE_USER_SELECTED_FILES": "readwrite",
    "REGISTER_APP_GROUPS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "26.2",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "ScoreEdit",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "INFOPLIST_KEY_CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "INFOPLIST_KEY_CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "INFOPLIST_KEY_CFBundleDisplayName": "ScoreEdit",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.music",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "nonisolated",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LD_RUNPATH_SEARCH_PATHS": [
        "$(inherited)",
        "@executable_path/../Frameworks",
    ],
])

let testSettings: SettingsDictionary = baseSettings.merging([
    "CODE_SIGN_STYLE": "Automatic",
    "MACOSX_DEPLOYMENT_TARGET": "26.2",
    "STRING_CATALOG_GENERATE_SYMBOLS": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
])


let project = Project(
    name: "ScoreEdit",
    settings: .settings(
        base: [
            "MACOSX_DEPLOYMENT_TARGET": "26.2",
        ]
    ),
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
                    ],
                    [
                        "CFBundleTypeName": "Plain Text",
                        "CFBundleTypeRole": "Editor",
                        "LSHandlerRank": "Alternate",
                        "LSItemContentTypes": ["public.plain-text"],
                        "CFBundleTypeExtensions": ["txt"],
                    ],
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
                .external(name: "CeolKitModel"),
                .external(name: "CeolKitParser"),
                .external(name: "CeolKitSVGRenderer"),
                .external(name: "Logging"),
                .external(name: "SVGKit"),
                .external(name: "SVGKitSwift"),
            ],
            settings: .settings(base: appSettings)
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

/*
 If we make a UI test suite, it should apply the test settings:
 settings: .settings(
  base: testSettings.merging([
      "TEST_TARGET_NAME": "ScoreEdit",
  ])
 )
 */
