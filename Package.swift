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
        .library(name: "AuthorUI", targets: ["AuthorUI"]),
        .executable(name: "AuthorAppPrototype", targets: ["AuthorAppPrototype"])
    ],
    targets: [
        .target(
            name: "AuthorData",
            exclude: [
                "Resources/AuthorData.xcdatamodeld"
            ],
            resources: [
                .copy("Resources/AuthorData.momd")
            ]
        ),
        .target(
            name: "AuthorUI",
            dependencies: ["AuthorData"]
        ),
        .executableTarget(
            name: "AuthorAppPrototype",
            dependencies: ["AuthorUI"],
            path: "Sources/AuthorApp",
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
