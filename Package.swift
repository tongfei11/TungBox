// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TungBox",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TungBox", targets: ["TungBox"])
    ],
    targets: [
        .executableTarget(
            name: "TungBox",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TungBoxTests",
            dependencies: ["TungBox"],
            path: "Tests"
        )
    ]
)
