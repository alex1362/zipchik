// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZIP",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ZIP", targets: ["ZIPApp"])],
    targets: [
        .executableTarget(name: "ZIPApp"),
        .testTarget(name: "ZIPAppTests", dependencies: ["ZIPApp"])
    ]
)
