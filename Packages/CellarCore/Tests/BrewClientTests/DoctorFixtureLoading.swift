import CryptoKit
import Foundation

/// `Fixtures/Doctor/`, read the way the tests consume it.
///
/// Every read here returns `Data`. Nothing in this loader decodes a fixture as
/// text, because one of them is invalid UTF-8 by construction and a loader that
/// decoded eagerly would substitute replacement characters before the parser
/// under test ever saw the bytes.
enum DoctorFixtureManifest {
    /// The fixtures as the tests actually consume them — the bundle copy, not
    /// the repository source. If `resources: [.copy("Fixtures")]` were dropped
    /// from `Package.swift`, this fails rather than silently reading a tree the
    /// built test bundle does not contain.
    static let root: URL = {
        guard let resourceURL = Bundle.module.resourceURL else {
            preconditionFailure("the BrewClientTests bundle has no resource URL")
        }
        return resourceURL.appendingPathComponent("Fixtures/Doctor")
    }()

    static let manifestName = "probe-manifest.txt"

    /// Not hashed by the manifest: a manifest cannot record its own digest, and
    /// the README changes whenever the prose does.
    static let unhashed: Set<String> = [manifestName, "README.md"]

    struct Contents: Sendable {
        /// `key=value` lines, verbatim.
        let values: [String: String]
        /// `sha256[path]=digest`.
        let digests: [String: String]
        /// `bytes[path]=count`.
        let byteCounts: [String: Int]
    }

    static func data(at path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    static func load() throws -> Contents {
        let text = try String(
            contentsOf: root.appendingPathComponent(manifestName),
            encoding: .utf8
        )

        var values: [String: String] = [:]
        var digests: [String: String] = [:]
        var byteCounts: [String: Int] = [:]

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
            values[key] = value

            if let name = bracketed(key, prefix: "sha256") {
                digests[name] = value
            } else if let name = bracketed(key, prefix: "bytes") {
                byteCounts[name] = Int(value)
            }
        }
        return Contents(values: values, digests: digests, byteCounts: byteCounts)
    }

    private static func bracketed(_ key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix + "["), key.hasSuffix("]") else { return nil }
        return String(key.dropFirst(prefix.count + 1).dropLast())
    }

    /// Every regular file under `Fixtures/Doctor/`, relative to it, excluding the
    /// files the manifest deliberately does not hash.
    static func filesOnDisk() throws -> Set<String> {
        let manager = FileManager.default
        guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }

        var found: Set<String> = []
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            guard unhashed.contains(path) == false else { continue }
            found.insert(path)
        }
        return found
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The three captures, named once so a suite never spells a path.
enum DoctorFixture {
    struct Streams: Sendable {
        let stdout: Data
        let stderr: Data
    }

    static func streams(of directory: String) throws -> Streams {
        Streams(
            stdout: try DoctorFixtureManifest.data(at: "\(directory)/stdout.txt"),
            stderr: try DoctorFixtureManifest.data(at: "\(directory)/stderr.txt")
        )
    }

    static var warningsRun: Streams { get throws { try streams(of: "warnings-run") } }
    static var cleanRun: Streams { get throws { try streams(of: "clean-run") } }
    static var oddGrouping: Streams { get throws { try streams(of: "odd-grouping") } }
}
