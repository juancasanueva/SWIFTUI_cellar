import Foundation

/// Reads a captured fixture as the tests consume it.
///
/// Every path goes through `FixtureManifest.root`, which is the **bundle** copy
/// rather than the repository source, so a fixture read here is a fixture whose
/// digest `ReleaseNotesFixtureManifestTests` already recomputed. There is
/// deliberately no way to read a file the manifest does not name.
///
/// The `headers(_:)` accessor is the addition this capability's fixtures needed:
/// rate-limit state is parsed from every response, so a captured body without its
/// captured headers would only be half a capture.
enum Fixture {
    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: FixtureManifest.root.appendingPathComponent(path))
    }

    static func text(_ path: String) throws -> String {
        try String(
            contentsOf: FixtureManifest.root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    /// A captured `*.headers.txt` parsed into the field dictionary an
    /// `HTTPURLResponse` would carry.
    ///
    /// The status line is dropped rather than parsed into a fake status: the
    /// status belongs to the response, and a test that wants one says so.
    /// Continuation lines are not folded, because HTTP/2 does not produce them
    /// and inventing support for a shape the captures cannot contain would be
    /// untested code in a test helper.
    static func headers(_ path: String) throws -> [String: String] {
        var fields: [String: String] = [:]
        for line in try text(path).split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("HTTP/") == false,
                  let separator = line.firstIndex(of: ":")
            else { continue }
            let name = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            fields[name] = value
        }
        return fields
    }
}
