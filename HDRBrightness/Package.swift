// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HDRBrightness",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HDRBrightness",
            targets: ["HDRBrightness"]
        ),
    ],
    targets: [
        .target(
            name: "HDRBrightness"
        ),
    ]
)
