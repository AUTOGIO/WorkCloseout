// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkCloseout",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkCloseoutCore", targets: ["WorkCloseoutCore"]),
        .executable(name: "work-closeout", targets: ["WorkCloseoutCLI"]),
        .executable(name: "WorkCloseout", targets: ["WorkCloseoutApp"])
    ],
    targets: [
        .target(name: "WorkCloseoutCore"),
        .executableTarget(name: "WorkCloseoutCLI", dependencies: ["WorkCloseoutCore"]),
        .executableTarget(name: "WorkCloseoutApp", dependencies: ["WorkCloseoutCore"]),
        .testTarget(name: "WorkCloseoutCoreTests", dependencies: ["WorkCloseoutCore"])
    ]
)
