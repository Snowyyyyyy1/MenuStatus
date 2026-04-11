import ProjectDescription

let project = Project(
    name: "MenuStatus",
    targets: [
        .target(
            name: "MenuStatus",
            destinations: .macOS,
            product: .app,
            bundleId: "com.snowyy.MenuStatus",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
                "SUFeedURL": .string(""),
                "SUPublicEDKey": .string(""),
            ]),
            sources: ["Sources/**"],
            resources: ["Sources/Resources/**"],
            dependencies: [
                .external(name: "Sparkle"),
                .external(name: "MenuBarExtraAccess"),
            ]
        ),
        .target(
            name: "MenuStatusTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.snowyy.MenuStatusTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "MenuStatus"),
            ]
        ),
    ]
)
