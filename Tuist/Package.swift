// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "Sparkle": .framework,
        "MenuBarExtraAccess": .framework,
    ]
)
#endif

let package = Package(
    name: "MenuStatusDependencies",
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
    ]
)
