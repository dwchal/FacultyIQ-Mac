// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FacultyIQ",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FacultyIQ",
            path: "Sources/FacultyIQ"
        ),
        .testTarget(
            name: "FacultyIQTests",
            dependencies: ["FacultyIQ"],
            path: "Tests/FacultyIQTests"
        ),
    ]
)
