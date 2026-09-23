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
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.5"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.1")
    ],
    targets: [
        // No pkgConfig: macOS doesn't ship a sqlite3.pc file for pkg-config
        // to find even though the SDK always has sqlite3.h + libsqlite3
        // (a known pain point for SwiftPM systemLibrary + sqlite3 on
        // macOS) — the modulemap links directly against the SDK header
        // instead, sidestepping pkg-config entirely.
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "Telemetree",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
                "CSQLite"
            ],
            path: "Sources/Telemetree",
            resources: [
                .copy("Resources/Icons"),
                .copy("Resources/Fonts")
            ]
        )
    ]
)
