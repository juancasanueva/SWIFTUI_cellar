//
//  UpdatePolicy.swift
//  Updates
//

/// What Cellar writes to the updater at launch.
///
/// The *decision* lives here and the *effect* lives at the one call site in the
/// app, which is what makes it testable against an in-memory updater instead of
/// against a source sweep. Cellar's own persisted preference is the authority:
/// neither a value baked into the bundle nor a value the updater framework
/// persisted on its own may decide whether Cellar reaches the network.
@MainActor
public enum AutomaticUpdateChecksPolicy {
    /// Writes the preference to the updater, exactly once, unconditionally.
    ///
    /// Unconditional on purpose. "Only write when it differs" is the obvious
    /// optimisation and it quietly removes the guarantee: the requirement is
    /// that *at every launch* the app writes its own setting, so that a value
    /// the framework persisted behind Cellar's back is overwritten rather than
    /// inspected.
    public static func apply(preference: Bool, to updater: any AppUpdating) {
        updater.automaticallyChecksForUpdates = preference
    }
}

/// Whether the explicit "Check for Updates…" command is live.
///
/// `nonisolated` and pure: it takes a `Bool` and returns a `Bool`, and the view
/// merely applies the answer. Nothing else may enter this decision — not whether
/// automatic checking is on, not whether the last check found anything, not
/// whether the app has ever checked. An explicit user action is its own consent,
/// so the only reason to refuse is that a check genuinely cannot run, which in
/// practice means one is already in flight.
public enum UpdateCommandEnablement {
    public static func isEnabled(canCheckForUpdates: Bool) -> Bool {
        canCheckForUpdates
    }
}
