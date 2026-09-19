// swift-tools-version: 5.9
// Engine + teaching-copy package so `swift test` can run the golden suite
// without SwiftUI. The iPad app still builds from StructuredNotesDesk.xcodeproj.

import PackageDescription

let package = Package(
    name: "StructuredNotesDesk",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "StructuredNotesDesk", targets: ["StructuredNotesDesk"])
    ],
    targets: [
        .target(
            name: "StructuredNotesDesk",
            path: "Sources/StructuredNotesDesk",
            exclude: [
                "DeskView.swift",
                "Components.swift",
                "StructuredNotesDesk.h"
            ]
        ),
        .testTarget(
            name: "StructuredNotesDeskTests",
            dependencies: ["StructuredNotesDesk"],
            path: "Tests/StructuredNotesDeskTests"
        )
    ]
)
