import BrewProcess
import DiskUsage
import Foundation
import Testing

@testable import BrewClient

/// The real `brew` binary, when this machine has one. Same constant and same
/// gate shape as `BrewIntegrationTests` — this layer's established skip idiom,
/// so a machine without Homebrew skips rather than fails.
private let realBrewPath = "/opt/homebrew/bin/brew"
private let hasRealBrew = FileManager.default.isExecutableFile(atPath: realBrewPath)

extension Tag {
    /// Spawns the real `brew`. Excluded from the fast inner loop with
    /// `swift test --skip tag:realBrew`.
    @Tag static var realBrew: Self
}

/// Roots for the binary at `path`, for the **suite gate only**.
///
/// `HomebrewRoots` derives the prefix from `executableURL` alone, so `prefix`,
/// `version` and `userCacheDirectory` are unread on this path. The gate has to
/// be synchronous and `DefaultBrewLocator.detect` is not, which is the only
/// reason this exists; the test re-resolves the marker from the *detected*
/// installation and asserts the two agree, so the shortcut cannot widen what is
/// observed.
private func gateRoots(forBrewAt path: String) -> HomebrewRoots {
    HomebrewRoots(
        installation: BrewInstallation(
            executableURL: URL(fileURLWithPath: path),
            prefix: .appleSilicon,
            version: DefaultBrewLocator.minimumVersion
        ),
        userCacheDirectory: FileManager.default.temporaryDirectory
    )
}

/// The fetch marker, resolved by the **shipped locator** rather than spelled
/// out. A fresh checkout that has never fetched has no marker, and that skips.
private let fetchMarker: URL? = hasRealBrew
    ? HomebrewRepositoryLocator
        .repository(for: gateRoots(forBrewAt: realBrewPath), access: SystemFileMetadataAccess())?
        .appendingPathComponent(HomebrewRepositoryLocator.fetchMarkerName)
    : nil

/// `system-health` SH4 sc3, as an observation rather than an argument about argv.
///
/// `DoctorCommandTests` and `DoctorSourceTests` pin the mechanism — one literal
/// argv element, classified `.read`, no environment override, no spine
/// collaborator — and not one of them can see the marker. The marker would be
/// moved by *Homebrew's own* auto-update, inside a process no argv assertion
/// reaches, which is why probe U14 had to measure it by hand. This runs it.
@Suite(
    "Real Homebrew doctor integration",
    .enabled(if: hasRealBrew && fetchMarker != nil),
    .tags(.realBrew),
    .timeLimit(.minutes(1))
)
struct DoctorIntegrationTests {
    @Test("Running doctor does not move the last-update reading")
    func runningDoctorDoesNotMoveTheLastUpdateReading() async throws {
        let installation = try #require(
            await DefaultBrewLocator().detect(configuredPath: nil).installation
        )
        let access = SystemFileMetadataAccess()
        let roots = HomebrewRoots(
            installation: installation,
            userCacheDirectory: FileManager.default.temporaryDirectory
        )
        let repository = try #require(
            HomebrewRepositoryLocator.repository(for: roots, access: access)
        )
        #expect(
            repository.appendingPathComponent(HomebrewRepositoryLocator.fetchMarkerName)
                == fetchMarker,
            "the gate and the detected installation resolved different markers"
        )

        // The pin is *asserted*, never re-applied: this is the exact environment
        // `BrewDoctorSource` composes for the run below, so a regression that
        // dropped `HOMEBREW_NO_AUTO_UPDATE` fails here instead of being papered
        // over by a test that set it itself.
        let environment = BrewEnvironment.current(
            commandOverrides: DoctorCommand.command.environmentOverrides
        )
        #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")

        // One `now` for both readings: the reading's `futureDated` arm is a
        // function of it, so a second `Date()` would be a second variable.
        let now = Date()
        let before = HomebrewUpdateReader.lastUpdate(roots: roots, now: now, access: access)
        // `.absent == .absent` would hold on a machine with no Homebrew at all,
        // which is exactly the vacuous pass this scenario is about.
        #expect(before.date != nil, "no readable fetch marker, so nothing was observed")

        let outcome = await BrewDoctorSource().run(using: installation)

        // Doctor must actually have run. `.unavailable` carries no evidence, and
        // a marker that did not move because nothing spawned proves nothing.
        let evidence = try #require(outcome.evidence, "brew doctor did not complete: \(outcome)")
        #expect(
            evidence.rawStdout.isEmpty == false || evidence.rawStderr.isEmpty == false,
            "brew doctor completed but wrote nothing, so no run was observed"
        )

        let after = HomebrewUpdateReader.lastUpdate(roots: roots, now: now, access: access)

        #expect(after == before, "brew doctor moved the fetch marker: \(before) -> \(after)")
    }
}
