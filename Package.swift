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
            name: "BabylonFish3",
            targets: ["BabylonFish3"]),
    ],
    dependencies: [
        // Dependencies go here
    ],
    targets: [
        .executableTarget(
            name: "BabylonFish3",
            dependencies: [],
            path: "Sources/BabylonFish3",
            exclude: ["README.md"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"], .when(platforms: [.macOS])),
                .unsafeFlags(["-framework", "Cocoa"], .when(platforms: [.macOS])),
                .unsafeFlags(["-framework", "CoreML"], .when(platforms: [.macOS])),
                .unsafeFlags(["-framework", "NaturalLanguage"], .when(platforms: [.macOS]))
            ]
        ),
    ]
)
