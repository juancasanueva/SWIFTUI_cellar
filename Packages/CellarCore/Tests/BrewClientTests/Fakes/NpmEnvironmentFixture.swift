import Foundation

@testable import BrewProcess

/// The detected npm the mutation suites point at. Nothing is ever spawned at
/// this path — every suite injects a launcher.
///
/// The sibling of `TestInstallation`, and separate from it for the reason the
/// two types are separate: an npm environment carries a version and a global
/// prefix that a brew installation has no field for.
enum NpmEnvironmentFixture {
    static func at(_ path: String, origin: NpmOrigin = .homebrew) -> NpmEnvironment {
        NpmEnvironment(
            executableURL: URL(fileURLWithPath: path),
            version: "10.9.2",
            prefix: URL(fileURLWithPath: "/opt/homebrew"),
            origin: origin
        )
    }

    static let detected = at("/opt/homebrew/bin/npm")
    static let volta = at("/Users/tester/.volta/bin/npm", origin: .volta)
}
