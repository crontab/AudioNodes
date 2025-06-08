// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioNodes",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "AudioNodes",
            targets: ["AudioNodes"]),
    ],
    dependencies: [
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AudioNodes",
            dependencies: [],
            path: "AudioNodes/Sources"
        ),
    ]
)
