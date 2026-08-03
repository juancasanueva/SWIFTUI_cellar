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
    /// - `HOMEBREW_NO_COLOR=1` and `HOMEBREW_NO_EMOJI=1` stop ANSI and emoji at
    ///   the source, which is what keeps `LogLine` verbatim *and* readable (D7).
    ///
    /// `HOMEBREW_COLOR` is deliberately **absent, at any value**. It is a
    /// *force*-colour boolean in brew (`env_config.rb:249-252`, declared
    /// `disabled_by: :HOMEBREW_NO_COLOR`), so its mere presence enables ANSI
    /// regardless of what it is set to: pinning it to `"0"` — which this did
    /// until M3-1 — forced colour **on** while this comment claimed the
    /// opposite (defect #7179).
    ///
    /// Suppression is an *environment* concern and never a filtering one.
    /// `brew-execution` BE2 requires a captured line to be delivered
    /// byte-identically, so nothing anywhere may strip, trim or rewrite an ESC
    /// byte out of `LogLine` to satisfy this.
    ///
    /// `HOMEBREW_NO_INSTALL_FROM_API` is deliberately absent: brew stays in its
    /// default API mode.
    public static let pinned: [String: String] = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_COLOR": "1",
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
