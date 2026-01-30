// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RampKit",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "RampKit",
            targets: ["RampKit"]
        ),
    ],
    targets: [
        .target(
            name: "RampKit",
            path: "Sources/RampKit",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("RAMPKIT_IOS")
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
