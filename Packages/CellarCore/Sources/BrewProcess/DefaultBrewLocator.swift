import Foundation

/// Finds Homebrew by probing the two standard prefixes, unless the user
/// configured a path.
///
/// Design decision D6 — strictness where the user made a choice: an
/// auto-probed prefix that fails validation *falls through* to the next
/// candidate, but a configured path **never** falls through. A silently ignored
/// custom path is a support nightmare, so it reports exactly why it was
/// rejected.
///
/// Detection is read-only by construction: the only command it ever runs is
/// `--version`.
public struct DefaultBrewLocator: BrewLocating {
    /// Homebrew releases before 4.0.0 predate the current formula API (PRD §8).
    public static let minimumVersion = BrewVersion(major: 4, minor: 0, patch: 0)

    /// Standard prefixes, in precedence order.
    static let standardCandidates: [(path: String, prefix: BrewPrefix, advisories: Set<Advisory>)] = [
        ("/opt/homebrew/bin/brew", .appleSilicon, []),
        ("/usr/local/bin/brew", .intelCarryOver, [.rosettaPrefix]),
    ]

    private let probe: any ExecutableProbing
    private let launcher: any ProcessLaunching

    public init(
        probe: any ExecutableProbing = DefaultExecutableProbe(),
        launcher: any ProcessLaunching = SystemProcessLauncher()
    ) {
        self.probe = probe
        self.launcher = launcher
    }

    public func detect(configuredPath: URL?) async -> BrewDetectionState {
        if let configuredPath {
            return await detectConfigured(configuredPath)
        }
        return await detectStandard()
    }

    /// Validates the user's path and reports the outcome as-is — no fallback.
    private func detectConfigured(_ configuredPath: URL) async -> BrewDetectionState {
        guard probe.exists(at: configuredPath) else {
            return .configuredPathMissing(configuredPath)
        }

        let resolved = probe.resolvingSymlinks(at: configuredPath)
        switch await validate(resolved) {
        case .success(let version):
            return .detected(
                BrewInstallation(
                    executableURL: resolved,
                    prefix: .custom(configuredPath),
                    version: version
                )
            )
        case .failure(let reason):
            return .invalid(configuredPath, reason)
        }
    }

    /// Probes the standard prefixes in order, falling through on failure.
    private func detectStandard() async -> BrewDetectionState {
        for candidate in Self.standardCandidates {
            let url = URL(fileURLWithPath: candidate.path)
            guard probe.exists(at: url) else { continue }

            let resolved = probe.resolvingSymlinks(at: url)
            guard case .success(let version) = await validate(resolved) else { continue }

            return .detected(
                BrewInstallation(
                    executableURL: url,
                    prefix: candidate.prefix,
                    version: version,
                    advisories: candidate.advisories
                )
            )
        }
        return .absent
    }

    /// Runs the three checks in order: executable, genuine Homebrew, recent
    /// enough. Exactly one reason comes back on failure.
    private func validate(_ url: URL) async -> Result<BrewVersion, BrewValidationError> {
        guard probe.isExecutableRegularFile(at: url) else {
            return .failure(.notExecutable(url))
        }

        let output: String
        do {
            output = try await readVersionOutput(at: url)
        } catch {
            return .failure(.probeFailed(url, message: String(describing: error)))
        }

        guard let version = BrewVersion.parse(output) else {
            return .failure(.notHomebrew(url, output: output))
        }
        guard version >= Self.minimumVersion else {
            return .failure(.versionTooOld(version, minimum: Self.minimumVersion))
        }
        return .success(version)
    }

    /// Runs `--version` and returns its trimmed stdout.
    ///
    /// Deliberately spawned directly rather than through `BrewRunner`: the
    /// runner needs a validated installation, and this is what validates it.
    private func readVersionOutput(at url: URL) async throws -> String {
        let process = try launcher.launch(
            ProcessSpec(
                executableURL: url,
                arguments: ["--version"],
                environment: BrewEnvironment.current()
            )
        )

        var splitter = LineSplitter()
        var lines: [LogLine] = []
        for await chunk in process.output {
            lines.append(contentsOf: splitter.consume(chunk))
        }
        lines.append(contentsOf: splitter.flush())
        _ = await process.waitForTermination()

        return lines
            .filter { $0.stream == .stdout }
            .map(\.text)
            .joined(separator: "\n")
    }
}
