// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftyBencode",
    platforms: [
        // Add support for all platforms starting from a specific version.
        .macOS(.v10_12),
        .iOS(.v9),
        .watchOS(.v2),
        .tvOS(.v9)
    ],
    products: [
        .library(name: "SwiftyBencode", targets: ["SwiftyBencode"])
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMinor(from: "1.3.1"))
    ],
    targets: [
        .target(name: "SwiftyBencode", dependencies: ["CryptoSwift"])
    ]
)

