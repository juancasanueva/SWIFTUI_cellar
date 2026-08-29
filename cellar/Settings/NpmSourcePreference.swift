//
//  NpmSourcePreference.swift
//  cellar
//

import BrewProcess
import Foundation

/// Whether the npm source is on, and which npm the user chose.
///
/// Two values in `UserDefaults` behind one type taking an injectable suite —
/// `AutomaticUpdateChecks`' shape, for the same reason: a preference whose
/// storage is only reachable through `.standard` cannot be tested without
/// writing to the developer's own defaults.
///
/// **Off is the default, and it is the absence of a stored value rather than a
/// registered `false`.** `UserDefaults.bool(forKey:)` answers `false` for a key
/// nobody has written, which is exactly the required behaviour and needs no
/// registration step that a future refactor could drop.
///
/// Not SwiftData: this gates whether a subprocess may run at all, and it has to
/// be readable before any store opens.
/// `nonisolated`: a preference read is a `UserDefaults` lookup and the
/// disclosure below is a pure projection. Neither touches the view hierarchy, so
/// neither needs the app target's default main-actor isolation — the discipline
/// `ArtifactLocator` already follows.
nonisolated struct NpmSourcePreference {
    static let enabledKey = "npm.sourceEnabled"
    static let pathKey = "npm.configuredPath"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nonmutating set` because the storage is the defaults domain, not this
    /// value: a `let` binding held by a view can still record the user's answer.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// The npm the user pointed Cellar at, or `nil` to discover one.
    ///
    /// A blank or whitespace-only field reads as `nil`. A user who clears the
    /// field means "go back to finding it yourself", and a `URL` built from an
    /// empty string would instead send detection looking for a binary called
    /// nothing — and report it as a configured path that failed.
    var configuredPath: URL? {
        get {
            let text = (defaults.string(forKey: Self.pathKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : URL(fileURLWithPath: text)
        }
        nonmutating set {
            defaults.set(newValue?.path ?? "", forKey: Self.pathKey)
        }
    }
}

/// Everything the npm Settings group renders, derived from detection.
///
/// The view holds no state logic: it lays out these strings. Each one is `nil`
/// when there is nothing to say, so a row is *absent* rather than showing a
/// placeholder — the same discipline the brew version row already follows.
nonisolated struct NpmSettingsDisclosure: Equatable {
    let path: String?
    let version: String?
    let prefix: String?
    let origin: String?
    /// What to say when there is nothing detected. `nil` when there is.
    let note: String?
    /// What belongs in the path field: what the user configured, never what was
    /// discovered. Filling it from a discovery would turn a guess into a choice
    /// the user never made, and would then be reported back as their choice
    /// failing if that npm ever moved.
    let configuredPathText: String

    init(state: NpmDetectionState, configuredPath: URL? = nil) {
        configuredPathText = configuredPath?.path ?? ""

        guard let environment = state.environment else {
            path = nil
            version = nil
            prefix = nil
            origin = nil
            note = Self.note(for: state)
            return
        }

        path = environment.executableURL.path
        version = "npm " + environment.version
        prefix = environment.prefix.path
        origin = environment.origin.displayName
        note = nil
    }

    /// One sentence per undetected state.
    ///
    /// Four different things went wrong — or did not go wrong at all — and the
    /// user's next step differs for each. "npm not detected" for a path they
    /// typed that is not executable would send them looking for an install they
    /// already have.
    private static func note(for state: NpmDetectionState) -> String {
        switch state {
        case .detected:
            ""
        case .disabled:
            "Turn the npm source on to detect it"
        case .absent:
            "npm not detected"
        case .configuredPathMissing(let url):
            url.path + " no longer exists"
        case .invalid(let url, let reason):
            switch reason {
            case .notExecutable: url.path + " is not executable"
            case .notNpm: url.path + " is not npm"
            case .noGlobalPrefix: url.path + " could not report its global prefix"
            case .probeFailed: url.path + " could not be run"
            }
        }
    }
}
