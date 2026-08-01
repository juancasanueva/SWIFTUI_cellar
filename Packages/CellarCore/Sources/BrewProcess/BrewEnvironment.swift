import Foundation

/// Builds the environment every `brew` invocation runs with.
///
/// Threat response — environment inheritance: the environment is composed
/// explicitly rather than inherited wholesale. Only `PATH` and `HOME` are
/// carried over from the parent; the three normalization keys are pinned last
/// so a `HOMEBREW_*` value in the user's shell can never change how Cellar
/// drives brew, and nothing else (tokens, mirrors, install-from-API overrides)
/// leaks into the subprocess.
public enum BrewEnvironment {
    /// Values pinned on every invocation.
    ///
    /// - `HOMEBREW_NO_AUTO_UPDATE=1` keeps a read from silently mutating state.
    /// - `HOMEBREW_COLOR=0` and `HOMEBREW_NO_EMOJI=1` stop ANSI and emoji at the
    ///   source, which is what keeps `LogLine` verbatim *and* readable (D7).
    ///
    /// `HOMEBREW_NO_INSTALL_FROM_API` is deliberately absent: brew stays in its
    /// default API mode.
    public static let pinned: [String: String] = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_COLOR": "0",
        "HOMEBREW_NO_EMOJI": "1",
    ]

    /// Keys taken from the parent environment when present.
    public static let inheritedKeys = ["PATH", "HOME"]

    /// Composes the environment for a subprocess from `parent`.
    public static func compose(inheriting parent: [String: String]) -> [String: String] {
        var environment: [String: String] = [:]
        for key in inheritedKeys {
            environment[key] = parent[key]
        }
        return environment.merging(pinned) { _, pinned in pinned }
    }

    /// Composes the environment from the current process's environment.
    public static func current() -> [String: String] {
        compose(inheriting: ProcessInfo.processInfo.environment)
    }
}
