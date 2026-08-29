import BrewProcess
import Foundation
import Testing

@testable import BrewClient

/// The captured npm output under `Fixtures/Npm/`.
///
/// See `Fixtures/Npm/probe-manifest.txt` for the exact command, exit code and
/// provenance of every file, including which two were hand-authored and why.
enum NpmFixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Npm"),
            "missing Fixtures/Npm/\(name)"
        )
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    /// The fixture's bytes as the stdout the payload adapter would have seen.
    static func stdoutLines(_ name: String) throws -> [LogLine] {
        lines(try text(name), stream: .stdout)
    }

    static func stderrLines(_ name: String) throws -> [LogLine] {
        lines(try text(name), stream: .stderr)
    }

    static func lines(_ text: String, stream: LogLine.Stream) -> [LogLine] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { LogLine(stream: stream, text: String($0.element), sequence: $0.offset) }
    }
}
