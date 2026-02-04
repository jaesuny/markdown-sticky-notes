// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StickyNotes",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "StickyNotes",
            targets: ["StickyNotes"]
        )
    ],
    targets: [
        .executableTarget(
            name: "StickyNotes",
            path: "Sources/StickyNotes",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
