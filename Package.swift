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
            name: "BabylonFish",
            targets: ["BabylonFish"]),
    ],
    dependencies: [
        // Dependencies go here
    ],
    targets: [
        .executableTarget(
            name: "BabylonFish",
            dependencies: [],
            exclude: ["Resources"],
            resources: [
                // .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"], .when(platforms: [.macOS])),
                .unsafeFlags(["-framework", "Cocoa"], .when(platforms: [.macOS]))
            ]
        ),
    ]
)
