// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FoodDecisionCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "FoodDecisionCore", targets: ["FoodDecisionCore"]),
    ],
    targets: [
        .target(
            name: "FoodDecisionCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FoodDecisionCoreTests",
            dependencies: ["FoodDecisionCore"]
        ),
    ]
)

