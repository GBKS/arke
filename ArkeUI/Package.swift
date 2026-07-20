// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArkeUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ArkeUI",
            targets: ["ArkeUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/GBKS/hallmarks", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ArkeUI",
            dependencies: [
                .product(name: "Hallmarks", package: "hallmarks"),
            ],
            resources: [
                .process("Media.xcassets")
            ]
        ),
        .testTarget(
            name: "ArkeUITests",
            dependencies: ["ArkeUI"]
        ),
    ]
)
