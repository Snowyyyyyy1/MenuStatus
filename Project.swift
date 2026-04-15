import Foundation
import ProjectDescription

let environment = ProcessInfo.processInfo.environment
let marketingVersion = environment["MENU_STATUS_VERSION"] ?? "1.0"
let currentProjectVersion = environment["MENU_STATUS_BUILD"] ?? "1"
let feedURL = environment["MENU_STATUS_FEED_URL"] ?? ""
let publicEDKey = environment["MENU_STATUS_PUBLIC_ED_KEY"] ?? ""

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
                .external(name: "MenuBarExtraAccess"),
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
