// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SillyTavernServerRuntime",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "NodeMobileRuntime", targets: ["NodeMobileRuntime"])
    ],
    targets: [
        .binaryTarget(
            name: "NodeMobile",
            path: "Vendor/NodeMobile.xcframework"
        ),
        .target(
            name: "NodeMobileRuntime",
            dependencies: ["NodeMobile"],
            path: "SillyTavernServer/Runtime",
            exclude: [
                "ServerController.swift",
                "ControlClient.swift",
                "SillyTavernServer-Bridging-Header.h"
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .unsafeFlags(["-std=c++20"])
            ]
        )
    ]
)
