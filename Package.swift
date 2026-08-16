// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dsh-ios",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "DshClient", targets: ["DshClient"]),
        .executable(name: "dsh-spike", targets: ["dsh-spike"])
    ],
    targets: [
        .target(name: "DshClient"),
        .executableTarget(name: "dsh-spike", dependencies: ["DshClient"])
    ]
)
