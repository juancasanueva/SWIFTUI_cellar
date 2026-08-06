import Foundation

/// Reads a captured fixture as the tests consume it.
///
/// Every path goes through `FixtureManifest.root`, which is the **bundle** copy
/// rather than the repository source, so a fixture read here is a fixture whose
/// digest `FixtureManifestTests` already recomputed. There is deliberately no
/// way to read a file that the manifest does not name.
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

    /// The non-comment, non-blank rows of a captured corpus.
    ///
    /// The `Versions/` corpora carry a long provenance header recording the
    /// capture command, machine and measured split. That header is the point of
    /// the file, and it is not data.
    static func corpusRows(_ path: String) throws -> [String] {
        try text(path)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false && $0.hasPrefix("#") == false }
    }
}
