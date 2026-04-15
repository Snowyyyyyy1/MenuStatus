import ProjectDescription

let marketingVersion = Environment.appVersion.getString(default: "1.0")
let currentProjectVersion = Environment.appBuild.getString(default: "1")
let feedURL = Environment.appFeedUrl.getString(default: "")
let publicEDKey = Environment.appPublicEdKey.getString(default: "")

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
                "CFBundleShortVersionString": .string("$(MARKETING_VERSION)"),
                "CFBundleVersion": .string("$(CURRENT_PROJECT_VERSION)"),
                "SUFeedURL": .string(feedURL),
                "SUPublicEDKey": .string(publicEDKey),
                "SUEnableAutomaticChecks": .boolean(true),
                "SUAutomaticallyUpdate": .boolean(true),
            ]),
            sources: ["Sources/**"],
            resources: ["Sources/Resources/**"],
            dependencies: [
                .external(name: "Sparkle"),
            ],
            settings: .settings(base: [
                "MARKETING_VERSION": .string(marketingVersion),
                "CURRENT_PROJECT_VERSION": .string(currentProjectVersion),
            ])
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
