// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DayTrader",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "DayTrader", targets: ["DayTrader"])
    ],
    dependencies: [
        // Lightweight charting — swap for Charts (Apple) which is built-in on iOS 16+
        // No external deps needed; we use Swift Charts (Apple) and Combine
    ],
    targets: [
        .target(
            name: "DayTrader",
            path: "DayTrader"
        ),
        .testTarget(
            name: "DayTraderTests",
            dependencies: ["DayTrader"],
            path: "DayTraderTests"
        )
    ]
)
