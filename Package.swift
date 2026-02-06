// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BabylonFish",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BabylonFishLegacy",
            targets: ["BabylonFishLegacy"]),
        .executable(
            name: "BabylonFish2",
            targets: ["BabylonFish2"]),
    ],
    dependencies: [
        // Dependencies go here
    ],
    targets: [
        .executableTarget(
            name: "BabylonFishLegacy",
            dependencies: [],
            path: "Sources/BabylonFish",
            exclude: ["Resources"],
            resources: [
                // .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"], .when(platforms: [.macOS])),
                .unsafeFlags(["-framework", "Cocoa"], .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "BabylonFish2",
            dependencies: [],
            path: "Sources/BabylonFish2",
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"], .when(platforms: [.macOS])),
                .unsafeFlags(["-framework", "Cocoa"], .when(platforms: [.macOS]))
            ]
        ),
    ]
)
