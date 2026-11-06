// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Osprey",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OspreyCore", targets: ["OspreyCore"]),
        .executable(name: "Osprey", targets: ["Osprey"]),
    ],
    targets: [
        .target(
            name: "OspreyCore",
            path: "Sources/OspreyCore"
        ),
        .executableTarget(
            name: "Osprey",
            dependencies: [
                "OspreyCore",
            ],
            path: "Sources/Osprey"
        ),
    ]
)
