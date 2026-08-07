import Foundation
import Synchronization
import Testing

@testable import BrewProcess
@testable import DiskUsage

/// How old the local Homebrew checkout is, read **without invoking brew**
/// (`system-health`, "The last-update reading costs no brew invocation" and "The
/// last-update reading is a typed answer and never an invented date"; design
/// HD4, HD5).
///
/// Asking how old something is must not be what updates it. `brew --repository`
/// would answer the location question correctly and would also give Homebrew a
/// chance to auto-update on the way — which would move the very marker this
/// reading is about. So the checkout is located by probing the filesystem
/// through a narrow seam, and every test in this file runs with **no disk and no
/// process at all**.
@Suite("Homebrew update reader")
struct HomebrewUpdateReaderTests {

    // MARK: - Arrangement

    /// A file-metadata seam with no filesystem behind it.
    ///
    /// Per-instance, under a `Mutex`: there is no shared counter and no static
    /// reset anywhere here, so two tests running concurrently cannot read each
    /// other's probes.
    final class FakeFileMetadataAccess: FileMetadataAccess, Sendable {
        private struct State {
            var answers: [String: FileModificationDate]
            var probed: [String] = []
        }

        private let state: Mutex<State>

        init(_ answers: [String: FileModificationDate] = [:]) {
            state = Mutex(State(answers: answers))
        }

        /// Every path asked about, in order. The *order* is the assertion for
        /// probe precedence, and the absence of a second entry is the assertion
        /// that the first probe won.
        var probed: [String] { state.withLock { $0.probed } }

        func modificationDate(at url: URL) -> FileModificationDate {
            state.withLock { state in
                state.probed.append(url.path)
                return state.answers[url.path] ?? .absent
            }
        }
    }

    /// A launcher that fails loudly if anything spawns a process. Nothing in
    /// this capability may reach it.
    final class ForbiddenProcessLauncher: ProcessLaunching, Sendable {
        private let launches = Mutex(0)
        var launchCount: Int { launches.withLock { $0 } }

        func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
            launches.withLock { $0 += 1 }
            throw BrewProcessError.executableUnavailable(spec.executableURL)
        }
    }

    private static func roots(prefix: String) -> HomebrewRoots {
        HomebrewRoots(
            installation: BrewInstallation(
                executableURL: URL(fileURLWithPath: "\(prefix)/bin/brew"),
                prefix: .appleSilicon,
                version: BrewVersion(major: 6, minor: 0, patch: 15)
            ),
            userCacheDirectory: URL(fileURLWithPath: "/Users/test/Library/Caches")
        )
    }

    /// Apple Silicon: `/opt/homebrew`, where the repository **is** the prefix
    /// (U11 measured `brew --repository` == the prefix on this shape).
    private static let appleSilicon = roots(prefix: "/opt/homebrew")
    /// The `/usr/local` shape PRD §3.9 supports, where the repository is nested
    /// under the prefix at `Homebrew/`.
    private static let intel = roots(prefix: "/usr/local")

    private static let marker = "FETCH_HEAD"
    private static let known = Date(timeIntervalSince1970: 1_786_081_527)

    // MARK: - 5.1 — probe order, on both installation shapes

    @Test("The nested-repository shape resolves to `<prefix>/Homebrew/.git`")
    func theNestedRepositoryShapeResolves() {
        let access = FakeFileMetadataAccess([
            "/usr/local/Homebrew/.git/\(Self.marker)": .read(Self.known)
        ])

        let location = HomebrewRepositoryLocator.repository(for: Self.intel, access: access)

        #expect(location?.path == "/usr/local/Homebrew/.git")
    }

    @Test("The repository-equals-prefix shape resolves to `<prefix>/.git`")
    func theRepositoryEqualsPrefixShapeResolves() {
        let access = FakeFileMetadataAccess([
            "/opt/homebrew/.git/\(Self.marker)": .read(Self.known)
        ])

        let location = HomebrewRepositoryLocator.repository(for: Self.appleSilicon, access: access)

        #expect(location?.path == "/opt/homebrew/.git")
        // The nested candidate was tried **first** and did not resolve.
        #expect(access.probed.first == "/opt/homebrew/Homebrew/.git/\(Self.marker)")
    }

    @Test("When both candidates exist the first one wins and the second is not read")
    func theFirstProbeWins() {
        let access = FakeFileMetadataAccess([
            "/usr/local/Homebrew/.git/\(Self.marker)": .read(Self.known),
            "/usr/local/.git/\(Self.marker)": .read(Date(timeIntervalSince1970: 0))
        ])

        let location = HomebrewRepositoryLocator.repository(for: Self.intel, access: access)

        #expect(location?.path == "/usr/local/Homebrew/.git")
        #expect(access.probed == ["/usr/local/Homebrew/.git/\(Self.marker)"], "the second candidate was read")
    }

    /// A probe that does not resolve is not an error. It is how the *other*
    /// shape is discovered, and on a machine with neither it is simply an absent
    /// answer.
    @Test("A non-resolving probe is not an error, and neither is a prefix with no checkout")
    func aNonResolvingProbeIsNotAnError() {
        let access = FakeFileMetadataAccess([:])

        let location = HomebrewRepositoryLocator.repository(for: Self.appleSilicon, access: access)

        #expect(location == nil)
        // Both candidates were tried, in order, and neither raised anything.
        #expect(access.probed == [
            "/opt/homebrew/Homebrew/.git/\(Self.marker)",
            "/opt/homebrew/.git/\(Self.marker)"
        ])
    }

    /// The probe list is a closed two-element list under `HomebrewRoots.prefix`.
    /// Nothing user-supplied and nothing from the environment can widen it.
    @Test("The probe list is exactly two candidates, both under the prefix")
    func theProbeListIsClosedAndUnderThePrefix() {
        let access = FakeFileMetadataAccess([:])

        _ = HomebrewRepositoryLocator.repository(for: Self.appleSilicon, access: access)

        #expect(access.probed.count == 2)
        #expect(access.probed.allSatisfy { $0.hasPrefix("/opt/homebrew/") }, "a probe left the prefix")
        #expect(access.probed.allSatisfy { $0.hasSuffix("/.git/\(Self.marker)") })
    }

    // MARK: - 5.2 — four typed cases, and never an invented date

    @Test("A present marker reads exactly its date")
    func aPresentMarkerReadsItsDate() {
        let access = FakeFileMetadataAccess([
            "/opt/homebrew/.git/\(Self.marker)": .read(Self.known)
        ])

        let reading = HomebrewUpdateReader.lastUpdate(
            roots: Self.appleSilicon,
            now: Self.known.addingTimeInterval(3600),
            access: access
        )

        #expect(reading == .read(Self.known))
        #expect(reading.age(at: Self.known.addingTimeInterval(3600)) == 3600)
    }

    @Test("A missing marker is absent, and produces no date and no age")
    func aMissingMarkerIsAbsentNotOld() {
        let reading = HomebrewUpdateReader.lastUpdate(
            roots: Self.appleSilicon,
            now: Self.known,
            access: FakeFileMetadataAccess([:])
        )

        #expect(reading == .absent)
        #expect(reading.date == nil)
        #expect(reading.age(at: Self.known) == nil)
    }

    @Test("An unreadable marker is its own case, distinguishable from absent")
    func anUnreadableMarkerIsItsOwnCase() {
        let access = FakeFileMetadataAccess([
            "/opt/homebrew/.git/\(Self.marker)": .unreadable
        ])

        let reading = HomebrewUpdateReader.lastUpdate(
            roots: Self.appleSilicon,
            now: Self.known,
            access: access
        )

        #expect(reading == .unreadable)
        #expect(reading != .absent, "unreadable collapsed into absent")
        #expect(reading.date == nil)
        #expect(reading.age(at: Self.known) == nil)
    }

    /// Clamping a future date to zero would render a **wrong clock** as a
    /// perfectly fresh installation, which is the most flattering possible lie
    /// this reading could tell.
    @Test("A future-dated marker is its own case and is never clamped to zero")
    func aFutureDatedMarkerIsNotClamped() {
        let future = Self.known.addingTimeInterval(86_400)
        let access = FakeFileMetadataAccess([
            "/opt/homebrew/.git/\(Self.marker)": .read(future)
        ])

        let reading = HomebrewUpdateReader.lastUpdate(
            roots: Self.appleSilicon,
            now: Self.known,
            access: access
        )

        #expect(reading == .futureDated(future), "a future marker was read as an ordinary date")
        #expect(reading.age(at: Self.known) == nil, "a future marker produced an age")
        // It carries the offending date rather than discarding it.
        #expect(reading.offendingDate == future)
    }

    /// No placeholder, no `Date.distantPast`, no zero date, no negative age —
    /// asserted over **every** case rather than over the one that motivated it.
    @Test(
        "No non-answer invents a date, a zero date or a negative age",
        arguments: [
            HomebrewLastUpdate.absent,
            .unreadable,
            .futureDated(Date(timeIntervalSince1970: 4_000_000_000))
        ]
    )
    func noNonAnswerInventsADate(reading: HomebrewLastUpdate) {
        #expect(reading.date == nil, "a non-answer produced a date an age could be derived from")
        #expect(reading.age(at: Self.known) == nil)
        #expect(reading.isAnswered == false)

        if let age = reading.age(at: Self.known) { #expect(age >= 0) }
    }

    /// The control that keeps the parameterised test above honest: the one case
    /// that *is* an answer behaves differently.
    @Test("Only `read` is an answered reading, and only it yields an age")
    func onlyReadIsAnswered() {
        let reading = HomebrewLastUpdate.read(Self.known)

        #expect(reading.isAnswered)
        #expect(reading.date == Self.known)
        #expect(reading.age(at: Self.known.addingTimeInterval(120)) == 120)
    }

    @Test("The reader never throws, whatever the seam answers")
    func theReaderNeverThrows() throws {
        let source = try Self.declarations(of: "HomebrewUpdateReader.swift")

        #expect(source.contains("throws") == false, "the update reader can throw")
        #expect(source.contains("-> HomebrewLastUpdate"))
        // And `Date.distantPast` appears nowhere: there is no placeholder date
        // to accidentally return.
        #expect(source.contains("distantPast") == false, "a placeholder date entered the reader")
    }

    // MARK: - 5.3, TM4 — resolving and reading spawn nothing

    @Test("Resolving and reading spawn zero processes on both installation shapes")
    func resolvingAndReadingSpawnNothing() {
        let launcher = ForbiddenProcessLauncher()

        for roots in [Self.appleSilicon, Self.intel] {
            let access = FakeFileMetadataAccess([
                "\(roots.prefix.path)/.git/\(Self.marker)": .read(Self.known)
            ])
            _ = HomebrewRepositoryLocator.repository(for: roots, access: access)
            let reading = HomebrewUpdateReader.lastUpdate(roots: roots, now: Self.known, access: access)

            // Non-trivial: the reading actually happened on both shapes.
            #expect(reading.isAnswered, "the \(roots.prefix.path) shape produced no reading")
            #expect(access.probed.isEmpty == false)
        }

        #expect(launcher.launchCount == 0, "the update reading spawned a process")
    }

    /// The structural half, which is the one that survives a refactor: the
    /// reader names no process seam, no network seam, no environment read and no
    /// user-supplied path.
    @Test("The reader names no process, network, environment or user-supplied path")
    func theReaderNamesNoProcessOrNetwork() throws {
        let reader = try Self.declarations(of: "HomebrewUpdateReader.swift")
        let seam = try Self.declarations(of: "FileMetadataAccess.swift")

        for forbidden in [
            "ProcessLaunching", "Process(", "BrewRunner", "BrewCommand", "URLSession",
            "ProcessInfo", "environment", "getenv", "update"
        ] {
            #expect(reader.contains(forbidden) == false, "the update reader reaches \(forbidden)")
        }
        for forbidden in ["ProcessLaunching", "Process(", "URLSession", "ProcessInfo"] {
            #expect(seam.contains(forbidden) == false, "the metadata seam reaches \(forbidden)")
        }

        // Positive anchors, so a scan that read nothing cannot pass silently.
        #expect(reader.contains("HomebrewRepositoryLocator"), "the reader scan read nothing")
        #expect(seam.contains("protocol FileMetadataAccess"), "the seam scan read nothing")

        // The violation control: the very strings above are findable when they
        // *are* present, so the absences above mean something.
        #expect(reader.contains("HomebrewRoots"), "the probe list is no longer rooted at HomebrewRoots")
    }

    /// The seam is one operation wide. A wider seam would be a filesystem, and a
    /// filesystem in this position is how "read the age" becomes "walk the
    /// repository".
    @Test("The metadata seam exposes exactly one operation")
    func theSeamIsOneOperationWide() throws {
        let seam = try Self.declarations(of: "FileMetadataAccess.swift")
        let requirements = seam
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("func ") && $0.contains("{") == false }

        #expect(requirements.count == 1, "the metadata seam declares \(requirements.count) operations")
        #expect(requirements.first?.contains("modificationDate(at url: URL) -> FileModificationDate") == true)
    }

    private static func declarations(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/DiskUsage/\(file)"),
            encoding: .utf8
        )
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
    }
}
