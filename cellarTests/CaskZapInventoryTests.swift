//
//  CaskZapInventoryTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads this repository off disk to keep the documented uninstall story bound
/// to the code it describes.
///
/// Deliberately self-contained rather than importing `ReleasePipelineSources`:
/// the cask slice is a net-new, independently revertible change, and rollback
/// should be the deletion of a single file rather than an unpicking of a shared
/// helper. That is the same reason `UpdateProjectSources` and
/// `AppcastScriptSources` each redeclare the `#filePath` anchor — the test
/// runner promises nothing about the working directory.
nonisolated enum CaskZapSources {
    /// The repository root, found relative to this file.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static let runbookPath = "RELEASING.md"
    static let readmePath = "README.md"

    /// The two trees whose Swift declares where Cellar writes. `cellarTests/`
    /// is excluded on purpose: a test fixture writing to a temporary directory
    /// is not a shipped write root, and a zap must never be widened by one.
    static let scannedRoots = ["cellar", "Packages/CellarCore/Sources"]

    /// The shipped default `Bundle.main.bundleIdentifier ?? …` spells at every
    /// application-support site, so the scan resolves the identifier to the same
    /// value the app resolves at runtime.
    static let bundleIdentifier = "com.juancasanueva.cellar"

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    // MARK: - The documented inventory

    /// One `<class> <path>` row of the `zap-inventory` block in `RELEASING.md`.
    struct InventoryRow: Equatable {
        let classification: String
        let path: String
    }

    /// The rows of the fenced block whose info string is `zap-inventory`.
    ///
    /// Each row is split on its **first whitespace run**, never on every run:
    /// the class token contains no spaces, but `Application Support` does, so
    /// any other split would truncate half the inventory into nonsense.
    static func inventoryRows() throws -> [InventoryRow] {
        let lines = try text(runbookPath).components(separatedBy: "\n")
        guard let fence = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "```zap-inventory"
        }) else {
            return []
        }

        var rows: [InventoryRow] = []
        for line in lines[lines.index(after: fence)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { break }
            if trimmed.isEmpty { continue }
            guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let classification = String(trimmed[..<split])
            let path = trimmed[split...].drop { $0 == " " || $0 == "\t" }
            rows.append(InventoryRow(classification: classification, path: String(path)))
        }
        return rows
    }

    // MARK: - The source scan

    enum SearchDomain: String {
        case cachesDirectory
        case applicationSupportDirectory

        /// Where macOS puts this domain for the user, spelled the way a cask's
        /// `zap trash:` list spells it.
        var userRoot: String {
            switch self {
            case .cachesDirectory: "~/Library/Caches"
            case .applicationSupportDirectory: "~/Library/Application Support"
            }
        }
    }

    enum Classification {
        /// The expression names a Cellar-owned root.
        case appending
        /// The bare directory is handed to something else.
        case passThrough
    }

    struct Occurrence {
        let file: String
        let line: Int
        let domain: SearchDomain
        let classification: Classification
        /// `lines[i ... i+3]`, joined.
        let forwardWindow: String
        /// `lines[i-3 ... i+3]`, joined.
        let symmetricWindow: String
        /// The root this occurrence declares, for an `appending` occurrence.
        let writeRoot: String?
    }

    /// Every `*.swift` under the scanned roots, in a stable order.
    static func swiftFiles() -> [URL] {
        scannedRoots.flatMap { root -> [URL] in
            guard let enumerator = FileManager.default.enumerator(
                at: url(root), includingPropertiesForKeys: nil
            ) else { return [] }
            return enumerator
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        }
        .sorted { $0.path < $1.path }
    }

    private static let searchDomainPattern =
        #"FileManager\.default\.urls\(for: \.(cachesDirectory|applicationSupportDirectory), in: \.userDomainMask\)"#

    /// Every use of a user-domain search directory in shipped source, classified.
    ///
    /// The forward window is **four** lines because the widest shipped shape
    /// spans exactly that — `CatalogStore.defaultDirectory` and
    /// `PersistenceContainer.defaultDirectory` both put their
    /// `.appendingPathComponent(` three lines below the `urls(for:in:)` call.
    /// Narrowing it to three would silently reclassify both application-support
    /// roots as pass-throughs and empty the scan of everything that matters.
    ///
    /// The pass-through window is **symmetric** because `HomebrewRoots(` opens
    /// above the match at three sites and closes below it at the other two.
    static func searchDomainOccurrences() throws -> [Occurrence] {
        let regex = try NSRegularExpression(pattern: searchDomainPattern)
        var occurrences: [Occurrence] = []

        for file in swiftFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n")

            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let domainRange = Range(match.range(at: 1), in: line),
                      let domain = SearchDomain(rawValue: String(line[domainRange]))
                else { continue }

                let forward = window(lines, from: index, to: index + 3)
                let symmetric = window(lines, from: index - 3, to: index + 3)
                let appends = forward.contains(".appendingPathComponent(")

                occurrences.append(
                    Occurrence(
                        file: file.lastPathComponent,
                        line: index + 1,
                        domain: domain,
                        classification: appends ? .appending : .passThrough,
                        forwardWindow: forward,
                        symmetricWindow: symmetric,
                        writeRoot: appends ? writeRoot(domain: domain, in: forward) : nil
                    )
                )
            }
        }
        return occurrences
    }

    /// Every write root the shipped source declares.
    static func discoveredWriteRoots() throws -> Set<String> {
        Set(try searchDomainOccurrences().compactMap(\.writeRoot))
    }

    private static func window(_ lines: [String], from lower: Int, to upper: Int) -> String {
        let start = max(lower, 0)
        let end = min(upper, lines.count - 1)
        guard start <= end else { return "" }
        return lines[start...end].joined(separator: "\n")
    }

    /// The first argument of the **first** `.appendingPathComponent(` in the
    /// window, resolved to a path under the domain's user root.
    ///
    /// A string literal contributes the substring before its first `/`, so
    /// `"Cellar/disk-usage-v1.json"` and `"Cellar"` both yield `Cellar` and an
    /// interpolated tail like `"Cellar/\(SecurityKit.advisoryCacheFileName)"` is
    /// safe by construction. The identifier `bundleIdentifier` resolves to the
    /// shipped default the same declaration spells.
    private static func writeRoot(domain: SearchDomain, in window: String) -> String? {
        guard let marker = window.range(of: ".appendingPathComponent(") else { return nil }
        let rest = window[marker.upperBound...]

        let component: String
        if rest.first == "\"" {
            component = String(rest.dropFirst().prefix { $0 != "\"" && $0 != "/" })
        } else {
            let identifier = rest.prefix { $0 != "," && $0 != ")" }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard identifier == "bundleIdentifier" else { return nil }
            component = bundleIdentifier
        }

        guard !component.isEmpty else { return nil }
        return "\(domain.userRoot)/\(component)"
    }
}

/// What `brew uninstall --cask --zap` claims, checked against what the app
/// actually writes.
///
/// An uninstall story that is quietly incomplete is worse than none, and every
/// milestone so far has added a cache file under `~/Library/Caches/Cellar`. The
/// point of this suite is that the next one fails here, in the repository where
/// the write is introduced, rather than silently outliving the app on a user's
/// disk.
@Suite("Cask zap inventory")
struct CaskZapInventoryTests {

    // MARK: - T1 — the inventory covers the source

    /// S6: direction is binding — **scan ⊆ inventory, never the reverse**. A
    /// `framework` row no source declares is correct and must not fail: AppKit,
    /// Foundation and Sparkle write three of the five measured roots, and no
    /// source scan can find them.
    @Test("Every write root the source declares is in the documented inventory")
    func everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory() throws {
        let discovered = try CaskZapSources.discoveredWriteRoots()
        #expect(!discovered.isEmpty)

        let documented = try CaskZapSources.inventoryRows()
            .filter { $0.classification == "source" }
            .map(\.path)

        for root in discovered.sorted() {
            #expect(
                documented.contains(root),
                "the zap inventory in RELEASING.md has no `source` row for \(root)"
            )
        }
    }

    // MARK: - T2 — the scan is not empty, and it stops at Cellar's own roots

    /// S6's non-vacuity half, and DD-10.
    ///
    /// The pass-through clause is the most important assertion in this file.
    /// `HomebrewRoots` derives `~/Library/Caches/Homebrew` and
    /// `/opt/homebrew/Cellar`, which are **Homebrew's**, not Cellar's. A scan
    /// that treated those five hand-offs as Cellar write roots would push
    /// Homebrew's own bottle cache into a `zap trash:` list and delete it on
    /// every uninstall.
    @Test("The write-root scan is non-vacuous and every pass-through is a HomebrewRoots hand-off")
    func theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff() throws {
        let occurrences = try CaskZapSources.searchDomainOccurrences()
        let appending = occurrences.filter { $0.classification == .appending }
        let passThrough = occurrences.filter { $0.classification == .passThrough }

        let expected: Set<String> = [
            "~/Library/Application Support/com.juancasanueva.cellar",
            "~/Library/Caches/Cellar",
        ]
        #expect(try CaskZapSources.discoveredWriteRoots() == expected)

        #expect(appending.count >= 7)
        #expect(passThrough.count >= 5)
        for occurrence in passThrough {
            #expect(
                occurrence.symmetricWindow.contains("HomebrewRoots("),
                "\(occurrence.file):\(occurrence.line) hands a user directory to something that is not HomebrewRoots, so the scan cannot prove it is not a Cellar root"
            )
        }

        let rows = try CaskZapSources.inventoryRows()
        #expect(rows.count >= 5)
        #expect(rows.filter { $0.classification == "source" }.count >= 2)
    }

    // MARK: - T3 — what a zap cannot remove

    /// S7: Homebrew's `zap` offers `trash:`, `delete:`, `rmdir:`, `signal:`,
    /// `launchctl:`, `quit:`, `pkgutil:`, `script:` and `login_item:` — and
    /// nothing for the Keychain. Naming both items is the whole obligation; no
    /// code is added to delete them.
    @Test("The runbook names both Keychain items a zap cannot remove")
    func theRunbookNamesBothKeychainItemsAZapCannotRemove() throws {
        let runbook = try CaskZapSources.text(CaskZapSources.runbookPath)

        for service in [
            "com.juancasanueva.cellar.nvd-api-key",
            "com.juancasanueva.cellar.github-pat"
        ] {
            #expect(
                runbook.contains(service),
                "RELEASING.md must name \(service) as an item a zap cannot remove"
            )
        }
    }

    // MARK: - T4 — the install commands are commands

    /// S8: whole lines, not substrings, for the reason
    /// `runbookRecordsTheVersionPolicyAndItsOverride` already gives — a reader
    /// who has to assemble the command from two paragraphs has not been given a
    /// command.
    @Test("The README carries both brew commands as whole lines")
    func theReadmeCarriesBothBrewCommandsAsWholeLines() throws {
        let readme = try CaskZapSources.text(CaskZapSources.readmePath)
        let lines = readme
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for command in [
            "brew tap juancasanueva/cellar",
            "brew install --cask home-cellar"
        ] {
            #expect(
                lines.contains(command),
                "README.md must carry `\(command)` as a whole, copy-pasteable line"
            )
        }

        // The unambiguous form, because an unqualified token can later be
        // claimed by another tap, and the bundle the install actually places.
        #expect(readme.contains("juancasanueva/cellar/home-cellar"))
        #expect(readme.contains("cellar.app"))
    }
}
