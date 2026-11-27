// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XDRBright",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "XDRBright",
            targets: ["XDRBright"]
        ),
    ],
    dependencies: [
        .package(name: "HDRBrightness", path: "../HDRBrightness"),
    ],
    targets: [
        .executableTarget(
            name: "XDRBright",
            dependencies: [.product(name: "HDRBrightness", package: "HDRBrightness")]
        ),
    ]
)
