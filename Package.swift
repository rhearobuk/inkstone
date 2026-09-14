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
        .library(name: "AuthorData", targets: ["AuthorData"])
    ],
    targets: [
        .target(
            name: "AuthorData",
            resources: [
                .process("Resources/AuthorData.xcdatamodeld"),
                .copy("Resources/AuthorData.momd")
            ]
        ),
        .testTarget(
            name: "AuthorDataTests",
            dependencies: ["AuthorData"]
        )
    ]
)
