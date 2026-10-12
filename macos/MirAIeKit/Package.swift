// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MirAIeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MirAIeKit", targets: ["MirAIeKit"]),
        .executable(name: "miraie-probe", targets: ["miraie-probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/mqtt-nio.git", from: "2.9.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "MirAIeKit",
            dependencies: [
                .product(name: "MQTTNIO", package: "mqtt-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "miraie-probe",
            dependencies: ["MirAIeKit"]
        ),
        .testTarget(
            name: "MirAIeKitTests",
            dependencies: ["MirAIeKit"]
        ),
    ]
)
