// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blinko",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Blinko",
            path: "Sources/Blinko",
            swiftSettings: [
                .unsafeFlags(["-enforce-exclusivity=unchecked"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuickLookThumbnailing"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
