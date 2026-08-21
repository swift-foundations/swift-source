// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-source",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Source", targets: ["Source"]),
        .library(name: "Source Measurement", targets: ["Source Measurement"]),
        .library(name: "Source Profile", targets: ["Source Profile"]),
        .library(name: "Source Swift Format", targets: ["Source Swift Format"]),
        .library(name: "Source SwiftLint", targets: ["Source SwiftLint"]),
        .library(name: "Source Linter", targets: ["Source Linter"]),
        .library(name: "Source Execution", targets: ["Source Execution"]),
        .library(name: "Source Report", targets: ["Source Report"]),
        .library(name: "Source Repair", targets: ["Source Repair"]),
        .library(name: "Source Test Support", targets: ["Source Test Support"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-primitives/swift-source-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-diagnostic-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-standards/swift-fips-180-4.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-foundations/swift-json.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Source",
            dependencies: [
                .product(name: "Source Primitives", package: "swift-source-primitives")
            ]
        ),
        .target(
            name: "Source Measurement",
            dependencies: [
                "Source",
                .product(name: "Diagnostic Primitives", package: "swift-diagnostic-primitives"),
                .product(name: "JSON", package: "swift-json"),
            ]
        ),
        .target(
            name: "Source Profile",
            dependencies: [
                "Source Measurement",
                .product(name: "FIPS 180-4", package: "swift-fips-180-4"),
                .product(name: "JSON", package: "swift-json"),
            ]
        ),
        .target(
            name: "Source Swift Format",
            dependencies: ["Source Measurement", "Source Profile"]
        ),
        .target(
            name: "Source SwiftLint",
            dependencies: ["Source Measurement", "Source Profile"]
        ),
        .target(
            name: "Source Linter",
            dependencies: [
                "Source Measurement",
                "Source Profile",
                .product(name: "JSON", package: "swift-json"),
            ]
        ),
        .target(
            name: "Source Execution",
            dependencies: [
                "Source Measurement",
                "Source Profile",
                "Source Swift Format",
                "Source SwiftLint",
                "Source Linter",
            ]
        ),
        .target(
            name: "Source Report",
            dependencies: ["Source Measurement", "Source Profile", .product(name: "JSON", package: "swift-json")]
        ),
        .target(
            name: "Source Repair",
            dependencies: [
                "Source",
                "Source Measurement",
                "Source Profile",
                "Source Report",
                .product(name: "FIPS 180-4", package: "swift-fips-180-4"),
                .product(name: "JSON", package: "swift-json"),
            ]
        ),
        .target(
            name: "Source Test Support",
            dependencies: [
                "Source Execution",
                "Source Linter",
                "Source Repair",
                "Source Report",
            ]
        ),
        .testTarget(
            name: "Source Tests",
            dependencies: [
                "Source",
                "Source Measurement",
                "Source Profile",
                "Source Execution",
                "Source Linter",
                "Source Repair",
                "Source Report",
                "Source Test Support",
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
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
