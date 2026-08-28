// swift-tools-version: 6.0
import PackageDescription

// ponytail: no test target — this machine has Command Line Tools only, which ship neither
// XCTest nor swift-testing. Checks live in AgentchCore/SelfCheck.swift and run via
// `swift run Agentch --selfcheck`. Add a real test target if Xcode gets installed.
let package = Package(
    name: "Agentch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AgentchCore"),
        .executableTarget(name: "Agentch", dependencies: ["AgentchCore"]),
    ]
)
