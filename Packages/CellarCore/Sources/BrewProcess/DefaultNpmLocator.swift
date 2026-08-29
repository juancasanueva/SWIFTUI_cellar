import Foundation

/// Finds npm by probing a fixed list of candidates, unless the user configured
/// a path.
///
/// The same strictness rule `DefaultBrewLocator` follows (design D6): an
/// auto-probed candidate that fails validation *falls through* to the next one,
/// but a configured path **never** does. A silently ignored custom path is a
/// support nightmare — worse here than for brew, because the whole reason a user
/// types a path is that Cellar picked the wrong npm and they want a specific one.
///
/// Detection is read-only by construction: the only commands it ever runs are
/// `--version` and `prefix -g`.
public struct DefaultNpmLocator: NpmLocating {
    /// A place npm is installed, and what to call it.
    ///
    /// `pattern` distinguishes a candidate that is one fixed path from one that
    /// is "the newest Node under this root", which is the whole difference
    /// between Homebrew/Volta/fnm and nvm/mise.
    private struct Candidate {
        enum Shape {
            /// One path, relative to `$HOME` or absolute.
            case fixed(String)
            /// `<root>/<version>/bin/npm`, newest version first.
            case newestUnder(root: String)
        }

        let shape: Shape
        let origin: NpmOrigin
        /// Whether `shape`'s path is relative to the home directory.
        let underHome: Bool
    }

    /// Every place npm is looked for, in the order it is looked for.
    ///
    /// Homebrew first because this is a Homebrew app and a `brew install node`
    /// is the npm most of these users have. The two system prefixes before the
    /// per-project managers because they are the machine-wide answer; the
    /// managers after, in the order of how self-contained they are.
    private static let candidates: [Candidate] = [
        Candidate(shape: .fixed("/opt/homebrew/bin/npm"), origin: .homebrew, underHome: false),
        Candidate(shape: .fixed("/usr/local/bin/npm"), origin: .usrLocal, underHome: false),
        Candidate(shape: .fixed(".volta/bin/npm"), origin: .volta, underHome: true),
        Candidate(
            shape: .fixed("Library/Application Support/fnm/aliases/default/bin/npm"),
            origin: .fnm,
            underHome: true
        ),
        Candidate(shape: .newestUnder(root: ".nvm/versions/node"), origin: .nvm, underHome: true),
        Candidate(
            shape: .newestUnder(root: ".local/share/mise/installs/node"),
            origin: .mise,
            underHome: true
        ),
    ]

    private let probe: any ExecutableProbing
    private let directories: any DirectoryEnumerating
    private let launcher: any ProcessLaunching
    private let homeDirectory: URL

    public init(
        probe: any ExecutableProbing = DefaultExecutableProbe(),
        directories: any DirectoryEnumerating = DefaultDirectoryEnumerator(),
        launcher: any ProcessLaunching = SystemProcessLauncher(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.probe = probe
        self.directories = directories
        self.launcher = launcher
        self.homeDirectory = homeDirectory
    }

    public func detect(configuredPath: URL?) async -> NpmDetectionState {
        if let configuredPath {
            return await detectConfigured(configuredPath)
        }
        return await detectDiscovered()
    }

    /// Validates the user's path and reports the outcome as-is — no fallback.
    private func detectConfigured(_ configuredPath: URL) async -> NpmDetectionState {
        guard probe.exists(at: configuredPath) else {
            return .configuredPathMissing(configuredPath)
        }

        let resolved = probe.resolvingSymlinks(at: configuredPath)
        switch await validate(
            resolved,
            binDirectory: configuredPath.deletingLastPathComponent(),
            origin: .configured
        ) {
        case .success(let environment):
            return .detected(environment)
        case .failure(let reason):
            return .invalid(configuredPath, reason)
        }
    }

    /// Probes the candidates in order, falling through on failure.
    private func detectDiscovered() async -> NpmDetectionState {
        for candidate in Self.candidates {
            for url in urls(for: candidate) {
                guard probe.exists(at: url) else { continue }

                let resolved = probe.resolvingSymlinks(at: url)
                guard case .success(let environment) = await validate(
                    resolved,
                    binDirectory: url.deletingLastPathComponent(),
                    origin: candidate.origin
                ) else { continue }

                return .detected(environment)
            }
        }
        return .absent
    }

    /// The paths a candidate expands to, in the order they should be tried.
    private func urls(for candidate: Candidate) -> [URL] {
        func resolve(_ path: String) -> URL {
            candidate.underHome
                ? homeDirectory.appendingPathComponent(path)
                : URL(fileURLWithPath: path)
        }

        switch candidate.shape {
        case .fixed(let path):
            return [resolve(path)]
        case .newestUnder(let root):
            return Self.newestFirst(directories.subdirectories(of: resolve(root)))
                .map { $0.appendingPathComponent("bin/npm") }
        }
    }

    /// Version directories, newest first.
    ///
    /// Ordered numerically per dotted segment, not lexicographically: nvm's
    /// directories are `v9.4.0` and `v22.11.0`, and a string comparison puts the
    /// older one first because `9` > `2`. Anything that does not parse sorts
    /// last, in name order, so the result is deterministic either way — the
    /// choice is displayed in Settings, and a selection that changed between two
    /// runs over the same disk would be impossible to support.
    static func newestFirst(_ directories: [URL]) -> [URL] {
        directories
            .map { (url: $0, version: versionSegments(of: $0.lastPathComponent)) }
            .sorted { left, right in
                switch (left.version, right.version) {
                case (nil, nil): return left.url.lastPathComponent < right.url.lastPathComponent
                case (nil, _): return false
                case (_, nil): return true
                case (let lhs?, let rhs?):
                    if lhs == rhs { return left.url.lastPathComponent < right.url.lastPathComponent }
                    return lhs.lexicographicallyPrecedes(rhs) == false
                }
            }
            .map(\.url)
    }

    /// `v22.11.0` and `22.11.0` both read as `[22, 11, 0]`. Anything else is
    /// `nil`, which sorts last rather than being coerced to zero.
    private static func versionSegments(of name: String) -> [Int]? {
        let body = name.hasPrefix("v") ? String(name.dropFirst()) : name
        guard body.isEmpty == false else { return nil }
        let segments = body.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var parsed: [Int] = []
        for segment in segments {
            guard let value = Int(segment), value >= 0 else { return nil }
            parsed.append(value)
        }
        return parsed.isEmpty ? nil : parsed
    }

    /// Runs the three checks in order: executable, genuinely npm, and able to
    /// answer where its global packages live. Exactly one reason comes back on
    /// failure.
    /// - Parameter binDirectory: where `node` must be resolvable from — the
    ///   directory the candidate was *found in*, never the symlink target's own.
    ///   The two validation probes below are the first invocations that would
    ///   fail if this were wrong, so they run under the same composed `PATH`
    ///   every later invocation does.
    private func validate(
        _ url: URL,
        binDirectory: URL,
        origin: NpmOrigin
    ) async -> Result<NpmEnvironment, NpmValidationError> {
        guard probe.isExecutableRegularFile(at: url) else {
            return .failure(.notExecutable)
        }

        let environment = NpmEnvironment.processEnvironment(
            binDirectory: binDirectory,
            inheriting: ProcessInfo.processInfo.environment
        )

        let versionOutput: String
        do {
            versionOutput = try await read(["--version"], at: url, environment: environment)
        } catch {
            return .failure(.probeFailed(message: String(describing: error)))
        }

        guard let version = Self.parseVersion(versionOutput) else {
            return .failure(.notNpm(output: versionOutput))
        }

        let prefixOutput: String
        do {
            prefixOutput = try await read(["prefix", "-g"], at: url, environment: environment)
        } catch {
            return .failure(.probeFailed(message: String(describing: error)))
        }

        guard prefixOutput.isEmpty == false, prefixOutput.hasPrefix("/") else {
            return .failure(.noGlobalPrefix)
        }

        return .success(
            NpmEnvironment(
                executableURL: url,
                binDirectory: binDirectory,
                version: version,
                prefix: URL(fileURLWithPath: prefixOutput),
                origin: origin
            )
        )
    }

    /// npm's own version, or `nil` when the output is some other program's.
    ///
    /// The rule is "it parses as a version", not "it is at least version N".
    /// There is deliberately no minimum: the two read commands and the two
    /// mutations this capability issues have been stable npm surface for a
    /// decade, so a floor would refuse working installations to enforce nothing.
    static func parseVersion(_ output: String) -> String? {
        let candidate = output
            .split(separator: "\n")
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        // Strip a prerelease or build suffix before checking the numbers, so
        // `11.0.0-pre.1` is a version and `git version 2.4.0` is not.
        let core = candidate.prefix { $0.isNumber || $0 == "." }
        guard core.count == candidate.prefix(core.count).count, core.isEmpty == false else {
            return nil
        }
        guard candidate.hasPrefix(core), core.first?.isNumber == true else { return nil }
        let segments = core.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ Int($0) != nil }) else { return nil }
        return candidate
    }

    /// Runs one read-only npm invocation and returns its trimmed stdout.
    ///
    /// Deliberately spawned directly rather than through `BrewRunner`: the runner
    /// needs a validated environment, and this is what validates it — the same
    /// reason `DefaultBrewLocator` spawns `--version` itself.
    private func read(
        _ arguments: [String],
        at url: URL,
        environment: [String: String]
    ) async throws -> String {
        let process = try launcher.launch(
            ProcessSpec(executableURL: url, arguments: arguments, environment: environment)
        )

        let (lines, exit) = await ProcessOutputCollector.drain(process)

        guard exit.status == 0 else { return "" }

        return lines
            .filter { $0.stream == .stdout }
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
