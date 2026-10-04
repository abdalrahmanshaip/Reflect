// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Reflect",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Reflect", targets: ["ReflectApp"]),
        .executable(name: "reflect-test-runner", targets: ["ReflectTestRunner"]),
        .executable(name: "reflect-ui-fixture", targets: ["ReflectUIFixture"])
    ],
    targets: [
        .target(
            name: "ReflectLib",
            path: "Sources/ReflectLib",
            swiftSettings: [
                // The explicit test runner uses @testable import in both debug
                // and release so the authoritative CLT runner remains honest.
                .unsafeFlags(["-enable-testing"])
            ]
        ),
        .executableTarget(
            name: "ReflectApp",
            dependencies: ["ReflectLib"],
            path: "Sources/ReflectAppMain"
        ),
        .executableTarget(
            name: "ReflectTestRunner",
            dependencies: ["ReflectLib"],
            path: "Tests/ReflectTestRunner"
        ),
        // Test-only synthetic UI launcher: never reads real histories; its store,
        // home, and secrets are temporary fixtures (see Tests/ReflectUIFixtureMain).
        .executableTarget(
            name: "ReflectUIFixture",
            dependencies: ["ReflectLib"],
            path: "Tests/ReflectUIFixtureMain"
        ),
        .testTarget(
            name: "ReflectSwiftTests",
            dependencies: ["ReflectTestRunner"],
            path: "Tests/ReflectSwiftTests",
            swiftSettings: [
                // Command Line Tools ship Swift Testing outside the default search path.
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
