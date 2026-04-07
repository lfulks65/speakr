// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Speakr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Speakr",
            targets: ["AppUI"]
        ),
        .library(
            name: "AudioCapture",
            targets: ["AudioCapture"]
        ),
        .library(
            name: "TranscriptionEngine",
            targets: ["TranscriptionEngine"]
        ),
        .library(
            name: "HotkeyService",
            targets: ["HotkeyService"]
        ),
        .library(
            name: "TextOutput",
            targets: ["TextOutput"]
        ),
        .library(
            name: "Settings",
            targets: ["Settings"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    ],
    targets: [
        // MARK: - Main App Target
        .executableTarget(
            name: "AppUI",
            dependencies: [
                "AudioCapture",
                "TranscriptionEngine",
                "HotkeyService",
                "TextOutput",
                "Settings",
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),

        // MARK: - Audio Capture Module
        .target(
            name: "AudioCapture",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Foundation"),
            ]
        ),

        // MARK: - Transcription Engine Module
        .target(
            name: "TranscriptionEngine",
            dependencies: [
                "AudioCapture",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Combine"),
            ]
        ),

        // MARK: - Hotkey Service Module
        .target(
            name: "HotkeyService",
            dependencies: [
                "Settings",
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        ),

        // MARK: - Text Output Module
        .target(
            name: "TextOutput",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("ApplicationServices"),
            ]
        ),

        // MARK: - Settings Module
        .target(
            name: "Settings",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Foundation"),
            ]
        ),

        // MARK: - Test Targets
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"]
        ),
        .testTarget(
            name: "TranscriptionEngineTests",
            dependencies: ["TranscriptionEngine", "AudioCapture"]
        ),
        .testTarget(
            name: "HotkeyServiceTests",
            dependencies: ["HotkeyService"]
        ),
        .testTarget(
            name: "TextOutputTests",
            dependencies: ["TextOutput"]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["Settings"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
