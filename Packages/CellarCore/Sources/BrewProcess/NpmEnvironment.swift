import Foundation

/// Where the selected `npm` came from.
///
/// Recorded rather than inferred from the path at the point of display, so
/// Settings can name the manager without re-deriving it from a string, and so a
/// future candidate can be added in exactly one place.
public enum NpmOrigin: String, Sendable, Hashable, CaseIterable {
    /// A path the user typed in Settings.
    case configured
    case homebrew
    case usrLocal
    case volta
    case fnm
    case nvm
    case mise

    /// What Settings calls it. Short, because it sits beside the path itself.
    public var displayName: String {
        switch self {
        case .configured: "Configured path"
        case .homebrew: "Homebrew"
        case .usrLocal: "/usr/local"
        case .volta: "Volta"
        case .fnm: "fnm"
        case .nvm: "nvm"
        case .mise: "mise"
        }
    }
}

/// One validated npm, and the environment its invocations run under.
///
/// A value rather than a store: detection produces one, every npm command is
/// handed one, and two of them describing the same binary are equal. That is
/// what lets "which npm did we run" be asserted by comparison instead of by
/// reading a log.
///
/// Threat response — environment inheritance: the environment is composed
/// explicitly, never inherited wholesale. Only `PATH` and `HOME` cross over from
/// the parent, and the seven pins are applied last, so a `npm_config_registry`
/// or an `NPM_TOKEN` in the user's shell cannot reach the subprocess.
///
/// The one rule that has no brew counterpart is the `PATH` **prepend**. `npm` is
/// `npm-cli.js` behind a `#!/usr/bin/env node` shebang: it resolves `node` from
/// `PATH` at exec time, and a GUI process launched from Finder inherits a `PATH`
/// that routinely has no `node` on it. Prepending the selected npm's own bin
/// directory is what makes the same binary the user's shell runs also runnable
/// from Cellar — and it is prepended rather than substituted so that a package's
/// own postinstall step can still find the ordinary system tools.
public struct NpmEnvironment: Sendable, Equatable, Hashable {
    public let executableURL: URL
    /// The directory `node` must be resolvable from.
    ///
    /// **Stored, not derived** (design D5 lists it as a member). Deriving it
    /// from `executableURL` was correct until a symlink was involved, and on the
    /// commonest install of all it always is: `/opt/homebrew/bin/npm` resolves
    /// two hops to `lib/node_modules/npm/bin/npm-cli.js`, whose own directory
    /// contains no `node`. Prepending *that* directory prepends one that cannot
    /// satisfy `#!/usr/bin/env node`, which is precisely the failure the prepend
    /// exists to prevent — and a GUI-launched Cellar then reports "npm not
    /// detected" on a Mac that plainly has npm.
    ///
    /// So identity follows the symlink and the launch directory does not: this
    /// is the directory the candidate was **found in**, which is the one the
    /// user's own shell resolves `node` from.
    public let binDirectory: URL
    /// The parsed output of `npm --version`.
    public let version: String
    /// The global prefix, from `npm prefix -g`. Where `-g` packages live.
    public let prefix: URL
    public let origin: NpmOrigin

    /// - Parameter binDirectory: where `node` is resolvable from. Defaults to
    ///   the executable's own directory, which is right for every unsymlinked
    ///   candidate and is what every call site outside detection means.
    public init(
        executableURL: URL,
        binDirectory: URL? = nil,
        version: String,
        prefix: URL,
        origin: NpmOrigin
    ) {
        self.executableURL = executableURL
        self.binDirectory = binDirectory ?? executableURL.deletingLastPathComponent()
        self.version = version
        self.prefix = prefix
        self.origin = origin
    }

    /// Values pinned on every npm invocation.
    ///
    /// - `NO_COLOR` and `npm_config_color` stop ANSI at the source. Suppression
    ///   is an environment concern and never a filtering one: `brew-execution`
    ///   BE2 requires captured lines to be delivered byte-identically, so no
    ///   ESC byte may ever be stripped out of a `LogLine` to satisfy this.
    /// - `npm_config_progress` removes the redrawing progress bar, which is
    ///   noise in a captured log rather than in a terminal.
    /// - `npm_config_update_notifier` stops npm advertising its own new version
    ///   in the middle of a package's output.
    /// - `npm_config_fund` and `npm_config_audit` suppress the two post-install
    ///   reports. Neither is a result Cellar presents, and `audit` additionally
    ///   costs a registry round trip on every install.
    /// - `npm_config_loglevel=warn` is npm's default, pinned so a value in
    ///   `~/.npmrc` cannot make the captured log either silent or unusable.
    ///
    /// No `npm_config_registry` is pinned at any value: the registry is the
    /// user's to configure in `~/.npmrc`, and `HOME` is inherited precisely so
    /// that stays true.
    public static let pinned: [String: String] = [
        "NO_COLOR": "1",
        "npm_config_color": "false",
        "npm_config_progress": "false",
        "npm_config_update_notifier": "false",
        "npm_config_fund": "false",
        "npm_config_audit": "false",
        "npm_config_loglevel": "warn",
    ]

    /// Keys taken from the parent environment when present.
    ///
    /// `HOME` so `~/.npmrc` applies — the user's registry, scopes and
    /// credentials are theirs, and a Cellar that ignored them would install
    /// different bytes than their shell does. `PATH` because it is the base the
    /// bin directory is prepended to.
    public static let inheritedKeys = ["PATH", "HOME"]

    /// Composes the environment for an npm subprocess from `parent`.
    ///
    /// A missing parent `PATH` yields the bin directory alone rather than a
    /// leading colon, which POSIX reads as "the current directory" — exactly the
    /// value that must never end up on a `PATH` Cellar composes.
    public func processEnvironment(inheriting parent: [String: String]) -> [String: String] {
        Self.processEnvironment(binDirectory: binDirectory, inheriting: parent)
    }

    /// The same composition, for a candidate that is not yet an `NpmEnvironment`.
    ///
    /// Detection has to run `--version` and `prefix -g` *before* it can build the
    /// value — the version and the prefix are what those two commands answer —
    /// so it needs the environment from the bin directory alone. Exposed as a
    /// static rather than by letting detection assemble a placeholder value with
    /// an empty version and a guessed prefix: a half-built `NpmEnvironment` is
    /// exactly the state this type exists to make unrepresentable.
    public static func processEnvironment(
        binDirectory: URL,
        inheriting parent: [String: String]
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for key in inheritedKeys {
            environment[key] = parent[key]
        }

        let bin = binDirectory.path
        if let inherited = parent["PATH"], inherited.isEmpty == false {
            environment["PATH"] = bin + ":" + inherited
        } else {
            environment["PATH"] = bin
        }

        environment.merge(pinned) { _, pinned in pinned }
        return environment
    }

    /// Composes the environment from the current process's environment.
    public func processEnvironment() -> [String: String] {
        processEnvironment(inheriting: ProcessInfo.processInfo.environment)
    }
}
