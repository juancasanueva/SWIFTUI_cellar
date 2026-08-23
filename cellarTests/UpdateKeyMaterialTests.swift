//
//  UpdateKeyMaterialTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Walks the repository looking for Ed25519-shaped key material.
///
/// Self-contained, like the other update suites, so the whole slice rolls back
/// by deleting its own files.
nonisolated enum UpdateKeyMaterialSources {
    /// Directories that are not "the repository": version-control internals,
    /// build output, and local tool state.
    static let uncheckedDirectories: Set<String> = [
        ".git", ".build", "build", ".swiftpm", "DerivedData", ".codegraph", ".atl"
    ]

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func repositoryFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: repositoryRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var files: [URL] = []
        while let candidate = enumerator.nextObject() as? URL {
            let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if uncheckedDirectories.contains(candidate.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            files.append(candidate)
        }
        return files
    }

    /// A found literal, with the file that carried it.
    struct Sighting: Sendable, Hashable {
        let path: String
        let literal: String
    }

    /// A raw Ed25519 key is 32 bytes, which base64-encodes to 43 characters plus
    /// one `=` of padding. The lookarounds are what stop the pattern firing on a
    /// 43-character window inside a longer base64 or hexadecimal blob — a
    /// resolved-package hash, for instance — which would otherwise make this a
    /// guard that fires on everything and therefore on nothing.
    static let ed25519Shape = "(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{43}=(?![A-Za-z0-9+/=])"

    static func sightings() throws -> (found: [Sighting], scanned: Int) {
        let expression = try NSRegularExpression(pattern: ed25519Shape)
        let rootPath = repositoryRoot.standardizedFileURL.path

        var found: [Sighting] = []
        var scanned = 0

        for file in repositoryFiles() {
            guard let data = try? Data(contentsOf: file) else { continue }
            scanned += 1
            let text = String(decoding: data, as: UTF8.self)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in expression.matches(in: text, range: range) {
                guard let matched = Range(match.range, in: text) else { continue }
                let path = file.standardizedFileURL.path
                    .replacingOccurrences(of: rootPath + "/", with: "")
                found.append(Sighting(path: path, literal: String(text[matched])))
            }
        }
        return (found, scanned)
    }
}

/// DD-12: the repository carries exactly one Ed25519-shaped literal, and it is
/// the public key the app ships.
///
/// This replaces the broad credential sweep the proposal originally sketched,
/// and the reason is worth keeping in front of whoever reads this next. A raw
/// Ed25519 **private** key is also 44 base64 characters with no header, so it is
/// byte-shape-identical to the **public** key this change commits on purpose.
/// Any pattern broad enough to catch one catches the other, and a filename
/// allow-list is a guard that passes because it was told to.
///
/// The exact-count form is false-positive-free and strictly stronger: a second
/// key appearing anywhere — in a fixture, a doc, a script, a committed export —
/// fails it, whatever the file is called.
///
/// **Residual gap, recorded rather than smoothed:** a private key committed in a
/// format that is *not* 44-character base64 evades both this and
/// `repositoryCarriesNoCredentialMaterial`.
@Suite("Update key material")
struct UpdateKeyMaterialTests {
    // MARK: - T20 — exactly one key-shaped literal, and it is the public key

    @Test("The only Ed25519-shaped literal in the repository is the bundled public key")
    func theOnlyKeyShapedLiteralIsTheBundledPublicKey() throws {
        let (found, scanned) = try UpdateKeyMaterialSources.sightings()

        #expect(found.count == 1)
        #expect(found.map(\.path) == [UpdateBundleSources.partialInfoPlist])

        let contents = try UpdateBundleSources.partialInfoPlistContents()
        let publicKey = try #require(contents["SUPublicEDKey"] as? String)
        #expect(found.map(\.literal) == [publicKey])

        // An absence is only proof if something counted the presences.
        #expect(scanned > 100)
    }
}
