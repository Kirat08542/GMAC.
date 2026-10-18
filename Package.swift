// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GLOTRemoteCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GLOTRemoteCore", targets: ["GLOTRemoteCore"]),
    ],
    targets: [
        .target(name: "GLOTRemoteCore"),
        .testTarget(name: "GLOTRemoteCoreTests", dependencies: ["GLOTRemoteCore"]),
    ]
)
