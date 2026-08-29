import Foundation
import Testing

@testable import BrewProcess

/// Detection resolves **at most one** npm, in a fixed priority order, and a path
/// the user configured never falls through to a discovered one.
///
/// The whole suite runs against scripted probes: no npm is installed, no
/// directory is walked, and no process is spawned, which is what makes every
/// branch — including "the configured path prints `git version 2.4.0`" —
/// reachable at all.
@Suite("npm detection")
struct NpmLocatorTests {
    private static let home = URL(fileURLWithPath: "/Users/tester")

    private static let homebrewNpm = "/opt/homebrew/bin/npm"
    private static let usrLocalNpm = "/usr/local/bin/npm"
    private static let voltaNpm = "/Users/tester/.volta/bin/npm"
    private static let fnmNpm =
        "/Users/tester/Library/Application Support/fnm/aliases/default/bin/npm"
    private static let nvmRoot = "/Users/tester/.nvm/versions/node"
    private static let miseRoot = "/Users/tester/.local/share/mise/installs/node"

    private static func locator(
        entries: [String: FakeExecutableProbe.Entry],
        responses: [FakeNpmLauncher.Key: FakeNpmLauncher.Response],
        directories: [String: [String]] = [:]
    ) -> (DefaultNpmLocator, FakeNpmLauncher, FakeExecutableProbe, FakeDirectoryEnumerator) {
        let probe = FakeExecutableProbe(entries: entries)
        let launcher = FakeNpmLauncher(responses: responses)
        let enumerator = FakeDirectoryEnumerator(children: directories)
        let locator = DefaultNpmLocator(
            probe: probe,
            directories: enumerator,
            launcher: launcher,
            homeDirectory: home
        )
        return (locator, launcher, probe, enumerator)
    }

    // MARK: - Priority

    @Test("Detection stops at the first candidate that validates")
    func priorityStopsAtTheFirstValidCandidate() async {
        // `/opt/homebrew/bin/npm` is absent, so `/usr/local` wins and Volta is
        // never even probed for a version.
        let (locator, launcher, _, _) = Self.locator(
            entries: [
                Self.usrLocalNpm: .executable,
                Self.voltaNpm: .executable,
            ],
            responses: FakeNpmLauncher.valid(Self.usrLocalNpm, prefix: "/usr/local")
                .merging(FakeNpmLauncher.valid(Self.voltaNpm)) { first, _ in first }
        )

        let state = await locator.detect(configuredPath: nil)

        guard case .detected(let environment) = state else {
            Issue.record("expected a detected npm, got \(state)")
            return
        }
        #expect(environment.executableURL.path == Self.usrLocalNpm)
        #expect(environment.origin == .usrLocal)
        #expect(environment.version == "10.9.2")
        #expect(environment.prefix.path == "/usr/local")
        #expect(launcher.launchedPaths.contains(Self.voltaNpm) == false)
    }

    @Test("Homebrew's npm outranks every version manager")
    func homebrewOutranksTheManagers() async {
        let (locator, _, _, _) = Self.locator(
            entries: [
                Self.homebrewNpm: .executable,
                Self.usrLocalNpm: .executable,
                Self.voltaNpm: .executable,
            ],
            responses: FakeNpmLauncher.valid(Self.homebrewNpm, prefix: "/opt/homebrew")
        )

        let state = await locator.detect(configuredPath: nil)

        #expect(state.environment?.executableURL.path == Self.homebrewNpm)
        #expect(state.environment?.origin == .homebrew)
    }

    @Test("The manager order is Volta, then fnm, then nvm, then mise")
    func managerOrderIsVoltaFnmNvmMise() async {
        let all: [String: FakeExecutableProbe.Entry] = [
            Self.voltaNpm: .executable,
            Self.fnmNpm: .executable,
            "\(Self.nvmRoot)/v22.3.0/bin/npm": .executable,
            "\(Self.miseRoot)/24.0.0/bin/npm": .executable,
        ]
        let directories = [
            Self.nvmRoot: ["v22.3.0"],
            Self.miseRoot: ["24.0.0"],
        ]
        let responses = all.keys.reduce(into: [FakeNpmLauncher.Key: FakeNpmLauncher.Response]()) {
            $0.merge(FakeNpmLauncher.valid($1)) { first, _ in first }
        }

        // Peel the winner off one at a time; each removal must promote exactly
        // the next candidate in the documented order.
        var remaining = all
        var origins: [NpmOrigin] = []
        for _ in 0..<4 {
            let (locator, _, _, _) = Self.locator(
                entries: remaining, responses: responses, directories: directories
            )
            let state = await locator.detect(configuredPath: nil)
            guard let environment = state.environment else {
                Issue.record("expected a detected npm from \(remaining.keys.sorted())")
                return
            }
            origins.append(environment.origin)
            remaining.removeValue(forKey: environment.executableURL.path)
        }

        #expect(origins == [.volta, .fnm, .nvm, .mise])
    }

    @Test("The newest installed Node wins under nvm and under mise")
    func newestNodeVersionWins() async {
        let newest = "\(Self.nvmRoot)/v22.11.0/bin/npm"
        let (locator, _, _, enumerator) = Self.locator(
            entries: [
                "\(Self.nvmRoot)/v20.9.0/bin/npm": .executable,
                "\(Self.nvmRoot)/v22.11.0/bin/npm": .executable,
                // Lexicographically the largest, numerically the smallest —
                // which is the whole reason the comparison is not a string one.
                "\(Self.nvmRoot)/v9.4.0/bin/npm": .executable,
            ],
            responses: FakeNpmLauncher.valid(newest),
            directories: [Self.nvmRoot: ["v20.9.0", "v22.11.0", "v9.4.0"]]
        )

        let state = await locator.detect(configuredPath: nil)

        #expect(state.environment?.executableURL.path == newest)
        #expect(state.environment?.origin == .nvm)
        #expect(enumerator.enumeratedPaths.contains(Self.nvmRoot))
    }

    // MARK: - The configured path never falls through

    @Test("A configured path that is not npm reports notNpm and does not fall back")
    func configuredNotNpmDoesNotFallBack() async {
        let configured = "/opt/tools/npm"
        let (locator, launcher, _, _) = Self.locator(
            entries: [configured: .executable, Self.homebrewNpm: .executable],
            responses: [
                .init(path: configured, arguments: ["--version"]): .out("git version 2.4.0")
            ].merging(FakeNpmLauncher.valid(Self.homebrewNpm)) { first, _ in first }
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: configured))

        #expect(state == .invalid(URL(fileURLWithPath: configured), .notNpm(output: "git version 2.4.0")))
        #expect(state.environment == nil)
        // Nothing was tried after the refusal — in particular not the perfectly
        // good Homebrew npm sitting right there.
        #expect(launcher.launchedPaths.contains(Self.homebrewNpm) == false)
    }

    @Test("A configured path that exists but is not executable is distinct from a missing one")
    func configuredNotExecutableIsDistinctFromMissing() async {
        let present = "/opt/tools/npm"
        let (notExecutable, _, _, _) = Self.locator(
            entries: [present: .notExecutable], responses: [:]
        )
        let (missing, missingLauncher, _, _) = Self.locator(entries: [:], responses: [:])

        let first = await notExecutable.detect(configuredPath: URL(fileURLWithPath: present))
        let second = await missing.detect(configuredPath: URL(fileURLWithPath: "/nope/npm"))

        #expect(first == .invalid(URL(fileURLWithPath: present), .notExecutable))
        #expect(second == .configuredPathMissing(URL(fileURLWithPath: "/nope/npm")))
        #expect(missingLauncher.recordedSpecs.isEmpty)
    }

    @Test("A configured path whose prefix probe fails is invalid, not detected")
    func configuredPrefixFailureIsInvalid() async {
        let configured = "/opt/tools/npm"
        let (locator, _, _, _) = Self.locator(
            entries: [configured: .executable],
            responses: [
                .init(path: configured, arguments: ["--version"]): .out("10.9.2"),
                .init(path: configured, arguments: ["prefix", "-g"]): .init(status: 1),
            ]
        )

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: configured))

        #expect(state.environment == nil)
        if case .invalid = state {} else {
            Issue.record("expected invalid, got \(state)")
        }
    }

    // MARK: - Absent

    @Test("No npm anywhere is a soft absent signal")
    func noCandidateYieldsAbsent() async {
        let (locator, launcher, _, _) = Self.locator(entries: [:], responses: [:])

        let state = await locator.detect(configuredPath: nil)

        #expect(state == .absent)
        #expect(launcher.recordedSpecs.isEmpty)
    }

    @Test("A candidate that exists but fails validation falls through to the next")
    func discoveredCandidateFallsThrough() async {
        let (locator, launcher, _, _) = Self.locator(
            entries: [Self.homebrewNpm: .executable, Self.usrLocalNpm: .executable],
            responses: [
                .init(path: Self.homebrewNpm, arguments: ["--version"]): .out("not a version")
            ].merging(FakeNpmLauncher.valid(Self.usrLocalNpm)) { first, _ in first }
        )

        let state = await locator.detect(configuredPath: nil)

        #expect(state.environment?.executableURL.path == Self.usrLocalNpm)
        #expect(launcher.launchedPaths.contains(Self.homebrewNpm))
    }

    // MARK: - Read-only

    @Test("Validation runs exactly two read-only npm invocations and nothing else")
    func validationIsReadOnly() async {
        let (locator, launcher, _, _) = Self.locator(
            entries: [Self.homebrewNpm: .executable],
            responses: FakeNpmLauncher.valid(Self.homebrewNpm)
        )

        _ = await locator.detect(configuredPath: nil)

        #expect(launcher.recordedArguments == [["--version"], ["prefix", "-g"]])
    }

    @Test("Both probes run under the composed npm environment, never the parent's")
    func probesRunUnderTheComposedEnvironment() async {
        let (locator, launcher, _, _) = Self.locator(
            entries: [Self.homebrewNpm: .executable],
            responses: FakeNpmLauncher.valid(Self.homebrewNpm)
        )

        _ = await locator.detect(configuredPath: nil)

        for spec in launcher.recordedSpecs {
            #expect(spec.environment["npm_config_loglevel"] == "warn")
            #expect(spec.environment["NO_COLOR"] == "1")
            #expect(spec.environment["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
            #expect(spec.environment.keys.contains { $0.hasPrefix("HOMEBREW_") } == false)
        }
    }

    @Test("A symlinked candidate is validated at its real path")
    func symlinksAreResolvedBeforeValidation() async {
        let real = "/opt/homebrew/Cellar/node/22.11.0/bin/npm"
        let (locator, launcher, _, _) = Self.locator(
            entries: [Self.homebrewNpm: .symlink(to: real), real: .executable],
            responses: FakeNpmLauncher.valid(real)
        )

        let state = await locator.detect(configuredPath: nil)

        #expect(state.environment?.executableURL.path == real)
        #expect(launcher.launchedPaths == [real, real])
    }

    /// The shape a real Homebrew `node` install actually has, and the defect the
    /// unit-3 integration pass found on it.
    ///
    /// `/opt/homebrew/bin/npm` resolves two hops to
    /// `lib/node_modules/npm/bin/npm-cli.js`, and **that** directory contains no
    /// `node`. npm is a `#!/usr/bin/env node` script, so prepending the resolved
    /// file's own directory to `PATH` prepends a directory that cannot satisfy
    /// the shebang — which is the exact failure the prepend exists to prevent
    /// (design D5: "npm is `npm-cli.js` with `#!/usr/bin/env node`; a GUI `PATH`
    /// has no `node`"). A GUI-launched Cellar then reports `npm not detected` on
    /// a Mac that plainly has npm.
    ///
    /// The launch directory is therefore the directory the candidate was **found
    /// in**, which is the one the user's own shell resolves `node` from, and it
    /// is a stored member of the environment exactly as D5 lists it.
    @Test("A symlinked candidate keeps the directory it was found in on PATH")
    func aSymlinkedCandidateKeepsItsLaunchDirectory() async throws {
        let real = "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js"
        let (locator, launcher, _, _) = Self.locator(
            entries: [Self.homebrewNpm: .symlink(to: real), real: .executable],
            responses: FakeNpmLauncher.valid(real)
        )

        let environment = try #require(await locator.detect(configuredPath: nil).environment)

        // Identity still follows the symlink: what ran is the real file.
        #expect(environment.executableURL.path == real)
        // The launch directory does not.
        #expect(environment.binDirectory.path == "/opt/homebrew/bin")
        #expect(
            environment.processEnvironment(inheriting: ["PATH": "/usr/bin"])["PATH"]
                == "/opt/homebrew/bin:/usr/bin"
        )

        // And the two validation probes ran under that same `PATH`, because they
        // are the first two invocations that would otherwise fail.
        #expect(launcher.recordedSpecs.isEmpty == false)
        for spec in launcher.recordedSpecs {
            #expect(spec.environment["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
        }
    }

    /// Triangulation: an unsymlinked candidate is unchanged — the launch
    /// directory is simply the file's own, as it always was.
    @Test("A plain candidate's launch directory is its own directory")
    func aPlainCandidateKeepsItsOwnDirectory() async throws {
        let (locator, _, _, _) = Self.locator(
            entries: [Self.voltaNpm: .executable],
            responses: FakeNpmLauncher.valid(Self.voltaNpm)
        )

        let environment = try #require(await locator.detect(configuredPath: nil).environment)

        #expect(environment.executableURL.path == Self.voltaNpm)
        #expect(environment.binDirectory.path == "/Users/tester/.volta/bin")
        #expect(
            environment.processEnvironment(inheriting: ["PATH": "/usr/bin"])["PATH"]
                == "/Users/tester/.volta/bin:/usr/bin"
        )
    }

    // MARK: - Disabled

    @Test("The disabled state carries no environment and is not absent")
    func disabledIsItsOwnState() {
        let disabled = NpmDetectionState.disabled

        #expect(disabled.environment == nil)
        #expect(disabled != .absent)
    }
}
