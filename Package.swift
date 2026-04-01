// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-source",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "Source",
            targets: ["Source"]
        )
    ],
    dependencies: [
        .package(path: "../../swift-primitives/swift-source-primitives")
    ],
    targets: [
        .target(
            name: "Source",
            dependencies: [
                .product(name: "Source Primitives", package: "swift-source-primitives")
            ]
        ),
        .testTarget(
            name: "Source Tests",
            dependencies: [
                "Source",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
