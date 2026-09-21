// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Telemetree",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Telemetree", targets: ["Telemetree"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0")
    ],
    targets: [
        .executableTarget(
            name: "Telemetree",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ],
            path: "Sources/Telemetree"
        )
    ]
)
