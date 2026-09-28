// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Reflect",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Reflect", targets: ["ReflectApp"]),
        .executable(name: "reflect-test-runner", targets: ["ReflectTestRunner"])
    ],
    targets: [
        .target(
            name: "ReflectLib",
            path: "Sources/ReflectLib"
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
