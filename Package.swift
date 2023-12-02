// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "photo-utils",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "PhotoUtils",
            targets: ["PhotoUtils"]),
    ],
    targets: [
        .target(
            name: "PhotoUtils"),
        .testTarget(
            name: "PhotoUtilsTests",
            dependencies: ["PhotoUtils"]),
    ]
)
