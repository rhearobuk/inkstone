// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuthorData",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "AuthorData", targets: ["AuthorData"]),
        .library(name: "AuthorAI", targets: ["AuthorAI"]),
        .library(name: "AuthorUI", targets: ["AuthorUI"]),
        .executable(name: "ScribePrototype", targets: ["ScribePrototype"])
    ],
    targets: [
        .target(
            name: "AuthorData",
            exclude: [
                "Resources/AuthorData.xcdatamodeld"
            ],
            resources: [
                .copy("Resources/AuthorData.momd"),
                .process("Resources/ExportTemplates")
            ]
        ),
        .target(name: "AuthorAI"),
        .testTarget(name: "AuthorAITests", dependencies: ["AuthorAI"]),
        .target(
            name: "AuthorUI",
            dependencies: ["AuthorData", "AuthorAI"]
        ),
        .executableTarget(
            name: "ScribePrototype",
            dependencies: ["AuthorUI"],
            path: "Sources/AuthorApp",
            exclude: [
                "AuthorApp.entitlements",
                "AuthorApp-macOS.entitlements"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "AuthorDataTests",
            dependencies: ["AuthorData"]
        ),
        .testTarget(
            name: "AuthorUITests",
            dependencies: ["AuthorUI"]
        )
    ]
)
