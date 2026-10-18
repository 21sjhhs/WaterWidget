// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WaterWidget",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WaterWidget", targets: ["WaterWidget"])
    ],
    targets: [
        .executableTarget(name: "WaterWidget")
    ]
)
