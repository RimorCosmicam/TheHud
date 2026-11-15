// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TheHud",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "HudCore", targets: ["HudCore"]),
        .executable(name: "hudshot", targets: ["hudshot"]),
        .executable(name: "hudcast", targets: ["hudcast"]),
    ],
    targets: [
        // Shared by the iOS app and the macOS preview tool. No platform-specific code here
        // beyond what Metal itself provides, so what the preview renders is what the app renders.
        .target(name: "HudCore", resources: [.copy("Resources/Fonts")]),

        // macOS-only: renders HudCore scenes to PNG without a device or a simulator.
        .executableTarget(name: "hudshot", dependencies: ["HudCore"]),

        // The input engine is free of UIKit precisely so this runs on a Mac and in CI.
        //
        // An executable rather than a .testTarget: XCTest and swift-testing both ship with
        // Xcode, and this machine has only the Command Line Tools. A plain binary that exits
        // non-zero runs identically here and on a GitHub runner, with nothing installed.
        .executableTarget(name: "hudtests", dependencies: ["HudCore"]),

        // macOS: HudCast, the Mac side of the desktop panel. It streams the screen, or one
        // window, to the phone over the local network and plays the phone's cursor and keys
        // back as real input. `scripts/build-hudcast.sh` wraps it as an app.
        .executableTarget(name: "hudcast", dependencies: ["HudCore"]),
    ]
)
