// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GymNetoKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "GymNetoKit", targets: ["GymNetoKit"])
    ],
    targets: [
        .target(name: "GymNetoKit"),
        .testTarget(name: "GymNetoKitTests", dependencies: ["GymNetoKit"])
    ]
)
