import Foundation
import Testing

@testable import BrewProcess

@Suite("Brew detection", .timeLimit(.minutes(1)))
struct DetectionTests {
    private let appleSiliconPath = "/opt/homebrew/bin/brew"
    private let intelPath = "/usr/local/bin/brew"
    private let customPath = "/Users/tester/homebrew/bin/brew"

    private func locator(
        entries: [String: FakeExecutableProbe.Entry],
        versions: [String: FakeVersionLauncher.Response]
    ) -> (DefaultBrewLocator, FakeExecutableProbe, FakeVersionLauncher) {
        let probe = FakeExecutableProbe(entries: entries)
        let launcher = FakeVersionLauncher(responses: versions)
        return (DefaultBrewLocator(probe: probe, launcher: launcher), probe, launcher)
    }

    // MARK: - Precedence

    @Test("The native prefix wins when both prefixes exist")
    func nativePrefixWinsOverIntel() async {
        let (locator, _, _) = locator(
            entries: [appleSiliconPath: .executable, intelPath: .executable],
            versions: [
                appleSiliconPath: .version("Homebrew 4.2.0"),
                intelPath: .version("Homebrew 4.2.0"),
            ]
        )

        let state = await locator.detect(configuredPath: nil)
        let installation = state.installation

        #expect(installation?.executableURL == URL(fileURLWithPath: appleSiliconPath))
        #expect(installation?.prefix == .appleSilicon)
        #expect(installation?.version == BrewVersion(major: 4, minor: 2, patch: 0))
        #expect(installation?.advisories.isEmpty == true)
    }

    @Test("Only the Intel prefix present resolves as a carry-over installation")
    func intelOnlyResolvesAsCarryOver() async {
        let (locator, _, _) = locator(
            entries: [intelPath: .executable],
            versions: [intelPath: .version("Homebrew 4.1.9")]
        )

        let state = await locator.detect(configuredPath: nil)
        let installation = state.installation

        #expect(installation?.executableURL == URL(fileURLWithPath: intelPath))
        #expect(installation?.prefix == .intelCarryOver)
    }

    @Test("A carry-over installation is advisory only, never degraded")
    func carryOverCarriesAnAdvisoryAndNothingElse() async {
        let (locator, _, _) = locator(
            entries: [intelPath: .executable],
            versions: [intelPath: .version("Homebrew 4.1.9")]
        )

        let state = await locator.detect(configuredPath: nil)
        let installation = state.installation

        #expect(installation?.advisories.contains(.rosettaPrefix) == true)
        // The state is fully detected: nothing is disabled, gated, or invalid.
        #expect(state == .detected(installation!))
        #expect(state.installGuidance == nil)
    }

    // MARK: - Absence

    @Test("No brew anywhere resolves to absent with install guidance")
    func absentCarriesInstallGuidance() async {
        let (locator, _, _) = locator(entries: [:], versions: [:])

        let state = await locator.detect(configuredPath: nil)

        #expect(state == .absent)
        #expect(state.installGuidance?.website == URL(string: "https://brew.sh"))
        #expect(state.installGuidance?.installCommand.contains("install.sh") == true)
    }

    // MARK: - Custom path validation

    @Test("A configured path that is not executable is invalid, not absent")
    func configuredPathNotExecutable() async {
        let (locator, _, _) = locator(
            entries: [customPath: .notExecutable],
            versions: [:]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))

        #expect(state == .invalid(
            URL(fileURLWithPath: customPath),
            .notExecutable(URL(fileURLWithPath: customPath))
        ))
    }

    @Test("An executable that is not Homebrew is invalid with its output")
    func configuredPathIsNotHomebrew() async {
        let (locator, _, _) = locator(
            entries: [customPath: .executable],
            versions: [customPath: .version("git version 2.4.0")]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))

        #expect(state == .invalid(
            URL(fileURLWithPath: customPath),
            .notHomebrew(URL(fileURLWithPath: customPath), output: "git version 2.4.0")
        ))
    }

    @Test("Homebrew below the 4.0.0 floor is invalid with both versions")
    func configuredPathIsTooOld() async {
        let (locator, _, _) = locator(
            entries: [customPath: .executable],
            versions: [customPath: .version("Homebrew 3.6.21")]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))

        #expect(state == .invalid(
            URL(fileURLWithPath: customPath),
            .versionTooOld(
                BrewVersion(major: 3, minor: 6, patch: 21),
                minimum: BrewVersion(major: 4, minor: 0, patch: 0)
            )
        ))
    }

    @Test("A symlinked configured path is resolved before it is probed")
    func symlinkIsResolvedBeforeProbing() async {
        let linkPath = "/usr/local/bin/brew-link"
        let (locator, probe, _) = locator(
            entries: [linkPath: .symlink(to: customPath), customPath: .executable],
            versions: [customPath: .version("Homebrew 4.2.0")]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: linkPath))

        #expect(state.installation?.executableURL == URL(fileURLWithPath: customPath))
        #expect(probe.probedPaths.contains(customPath))
        #expect(probe.probedPaths.contains(linkPath) == false)
    }

    // MARK: - Precedence and strictness of the configured path

    @Test("A valid configured path wins over an existing native prefix")
    func validCustomPathWinsOverAutoDiscovery() async {
        let (locator, _, _) = locator(
            entries: [appleSiliconPath: .executable, customPath: .executable],
            versions: [
                appleSiliconPath: .version("Homebrew 4.5.0"),
                customPath: .version("Homebrew 4.2.0"),
            ]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))
        let installation = state.installation

        #expect(installation?.executableURL == URL(fileURLWithPath: customPath))
        #expect(installation?.prefix == .custom(URL(fileURLWithPath: customPath)))
        #expect(installation?.version == BrewVersion(major: 4, minor: 2, patch: 0))
    }

    @Test("An invalid configured path never falls back to a working prefix")
    func invalidCustomPathDoesNotFallBack() async {
        let (locator, _, launcher) = locator(
            entries: [appleSiliconPath: .executable, customPath: .notExecutable],
            versions: [appleSiliconPath: .version("Homebrew 4.5.0")]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))

        #expect(state == .invalid(
            URL(fileURLWithPath: customPath),
            .notExecutable(URL(fileURLWithPath: customPath))
        ))
        #expect(state.installation == nil)
        // The native prefix was never even probed.
        #expect(launcher.recordedSpecs.isEmpty)
    }

    @Test("A configured path that no longer exists reports the missing path")
    func configuredPathMissing() async {
        let (locator, _, _) = locator(
            entries: [appleSiliconPath: .executable],
            versions: [appleSiliconPath: .version("Homebrew 4.5.0")]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))

        #expect(state == .configuredPathMissing(URL(fileURLWithPath: customPath)))
    }

    // MARK: - Safety

    @Test("Detection only ever runs --version, never a mutating command")
    func detectionRunsOnlyVersionProbes() async {
        let (locator, _, launcher) = locator(
            entries: [appleSiliconPath: .executable, intelPath: .executable],
            versions: [
                appleSiliconPath: .version("Homebrew 4.2.0"),
                intelPath: .version("Homebrew 4.2.0"),
            ]
        )

        _ = await locator.detect(configuredPath: nil)

        #expect(launcher.recordedArguments == [["--version"]])
        #expect(launcher.recordedSpecs.first?.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    }

    @Test("A prefix that fails validation falls through to the next one")
    func autoDiscoveryFallsThroughOnFailure() async {
        let (locator, _, _) = locator(
            entries: [appleSiliconPath: .executable, intelPath: .executable],
            versions: [
                appleSiliconPath: .version("Homebrew 3.6.21"),
                intelPath: .version("Homebrew 4.2.0"),
            ]
        )

        let state = await locator.detect(configuredPath: nil)

        #expect(state.installation?.prefix == .intelCarryOver)
    }

    @Test("An unprobeable binary reports why the probe failed")
    func probeFailureIsReported() async {
        let (locator, _, launcher) = locator(
            entries: [customPath: .executable],
            versions: [:]
        )
        launcher.failLaunch(with: POSIXError(.ENOMEM))

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: customPath))

        guard case .invalid(let url, .probeFailed(_, let message)) = state else {
            Issue.record("expected .invalid(.probeFailed), got \(state)")
            return
        }
        #expect(url == URL(fileURLWithPath: customPath))
        #expect(message.isEmpty == false)
    }
}
