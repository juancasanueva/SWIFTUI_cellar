//
//  AppcastScriptContractTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads `scripts/appcast.sh` off disk.
///
/// Self-contained rather than importing `ReleasePipelineSources`, on the same
/// reasoning that helper itself records: the publication half of this slice is
/// independently revertible, and rollback should be the deletion of one script
/// and one test file.
nonisolated enum AppcastScriptSources {
    static let scriptPath = "scripts/appcast.sh"

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static var scriptURL: URL { repositoryRoot.appendingPathComponent(scriptPath) }

    static func script() throws -> String {
        try String(contentsOf: scriptURL, encoding: .utf8)
    }

    /// Every invocation of `command` as a **command token**.
    ///
    /// A bare substring search is not good enough. `gh` occurs inside
    /// "github.com", which this script names in every enclosure URL, and `git`
    /// occurs inside "gitignored". A prohibition that fires on prose, or on a
    /// hostname, is a prohibition someone eventually weakens to shut it up — so
    /// it fires only on an actual invocation: start of line, or after
    /// whitespace, `;`, `|`, `&` or `(`, and followed by whitespace or the end
    /// of the line.
    static func commandInvocations(of command: String, in text: String) -> [String] {
        let pattern = "(?:^|[\\s;|&(])\(NSRegularExpression.escapedPattern(for: command))(?=\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line -> [String] in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard let matched = Range(match.range, in: text) else { return nil }
                let start = text[matched].hasPrefix(command) ? matched.lowerBound
                    : text.index(after: matched.lowerBound)
                return String(text[start...])
            }
        }
    }

    static func lines(naming needle: String, in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains(needle) }
    }
}

/// What the appcast script is allowed to do, and what it must never do.
///
/// Structural assertions over text, because the properties that matter here are
/// absences — "it cannot publish", "it cannot trace itself", "the key is never
/// written anywhere" — and an absence in a shell script is only provable by
/// reading it.
@Suite("Appcast script contract")
struct AppcastScriptContractTests {
    static let signPipeline = "printf '%s' \"$SPARKLE_PRIVATE_KEY\" |"

    // MARK: - T18 — the script's own posture

    /// It exists, it runs, and it fails loudly.
    @Test("The appcast script is executable and fails on the first error")
    func theScriptIsExecutableAndFailsLoudly() throws {
        let path = AppcastScriptSources.scriptURL.path

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.isExecutableFile(atPath: path))
        #expect(try AppcastScriptSources.script().contains("set -euo pipefail"))
    }

    /// It cannot publish, tag, retract, or pick a different repository.
    ///
    /// The release workflow's own guarantee is that it can only ever *create* a
    /// release: exactly one `gh release create`, zero `git`. A script invoked
    /// from that workflow with a `git` or a second `gh` in it would move the
    /// guarantee without touching the test that guards it, which is precisely
    /// why the script is asserted separately.
    @Test("The appcast script contains no git and no gh invocation")
    func theScriptCannotPublishOrSelectARepository() throws {
        let script = try AppcastScriptSources.script()

        #expect(AppcastScriptSources.commandInvocations(of: "git", in: script) == [])
        #expect(AppcastScriptSources.commandInvocations(of: "gh", in: script) == [])
        // The reader is only meaningful if it can find an invocation at all.
        #expect(!AppcastScriptSources.commandInvocations(of: "curl", in: script).isEmpty)
    }

    /// It never traces its own commands.
    ///
    /// `set -x` would echo the signing pipeline into the job log, and the
    /// signing pipeline is where the private key is.
    ///
    /// Matched as a command token rather than as a substring, on the same
    /// reasoning the workflow's own guard records: the script explains in a
    /// comment *why* it must never trace itself, and a prohibition that fires on
    /// prose about itself is a prohibition someone eventually deletes to shut it
    /// up.
    @Test("The appcast script never traces itself")
    func theScriptNeverTracesItself() throws {
        let script = try AppcastScriptSources.script()

        #expect(AppcastScriptSources.commandInvocations(of: "set -x", in: script) == [])
        // The reader is only meaningful if it can see a `set` that is really there.
        #expect(!AppcastScriptSources.commandInvocations(of: "set", in: script).isEmpty)
    }

    /// The signing tool is pinned by version **and** by digest.
    ///
    /// A tampered `sign_update` would sign the release with an attacker's key
    /// and every installed copy would accept the result, because the client
    /// only checks the signature against the key in its own bundle. The version
    /// alone does not prevent that; the digest does, and the verification aborts
    /// before anything is signed.
    @Test("The signing tool is pinned to 2.9.6 by a sha256 literal")
    func theSigningToolIsPinnedByDigest() throws {
        let script = try AppcastScriptSources.script()
        let digest = try NSRegularExpression(pattern: "\\b[0-9a-f]{64}\\b")
        let range = NSRange(script.startIndex..<script.endIndex, in: script)

        #expect(script.contains("2.9.6"))
        #expect(digest.numberOfMatches(in: script, range: range) == 1)
        #expect(script.contains("shasum -a 256"))
    }

    /// The private key reaches the tool on **stdin** and touches nothing else.
    ///
    /// Never a file, never a command argument, never a redirection target. The
    /// signing tool reads `--ed-key-file -` from standard input precisely so the
    /// key can come from a secret environment binding without ever being
    /// written down, which satisfies the invariant by construction rather than
    /// by remembering to clean up afterwards.
    @Test("The private key is only ever piped on stdin")
    func thePrivateKeyIsOnlyEverPipedOnStdin() throws {
        let script = try AppcastScriptSources.script()
        let naming = AppcastScriptSources.lines(naming: "SPARKLE_PRIVATE_KEY", in: script)

        #expect(!naming.isEmpty)
        for line in naming {
            let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            #expect(isComment || line.contains(Self.signPipeline), "unsafe use: \(line)")
            #expect(!line.contains(">"), "the key must never be a redirection target: \(line)")
        }
        #expect(script.contains("--ed-key-file -"))
        #expect(!script.contains("--ed-key-file \""))
    }

    // MARK: - T19 — the emitter and the validator agree on names

    /// Every name the offline validator requires appears in the emitter.
    ///
    /// **Honest about being textual.** The fixtures the validator is tested
    /// against are hand-authored, because running this script inside `swift
    /// test` would need the signing tool, a private key and network egress —
    /// three things this project forbids. So this proves the emitter and the
    /// validator agree on **names**, not on bytes. That limitation is stated
    /// rather than smoothed over.
    @Test("The emitter names every field the offline validator requires")
    func theEmitterNamesEveryFieldTheValidatorRequires() throws {
        let script = try AppcastScriptSources.script()
        let required = [
            "sparkle:edSignature",
            "length=",
            "sparkle:version",
            "sparkle:shortVersionString",
            "sparkle:minimumSystemVersion",
            "26.0",
            "<enclosure"
        ]

        for name in required {
            #expect(script.contains(name), "the emitter never writes \(name)")
        }
    }

    /// A prerelease tag produces no feed item at all.
    ///
    /// The same literal guard the release workflow uses, restated in the script
    /// so running it by hand behaves identically to running it in CI. A
    /// prerelease that reached the feed would be offered to every stable user,
    /// which the version comparison alone would not prevent.
    @Test("A prerelease tag exits before writing anything")
    func aPrereleaseTagExitsBeforeWritingAnything() throws {
        let script = try AppcastScriptSources.script()

        #expect(script.contains("case \"$GITHUB_REF_NAME\" in"))
        #expect(script.contains("*-*)"))
        #expect(script.contains("exit 0"))
    }
}
