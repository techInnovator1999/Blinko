// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blinko",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Blinko",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
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
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
                .linkedFramework("Intents"),
                // Sparkle.framework is embedded in Contents/Frameworks by scripts/build.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
