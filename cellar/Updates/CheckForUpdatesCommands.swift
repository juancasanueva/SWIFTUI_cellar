//
//  CheckForUpdatesCommands.swift
//  cellar
//

import SwiftUI
import Updates

/// The explicit "Check for Updates…" command, in the app menu after About.
///
/// An explicit user action is its own consent, so this stays reachable on every
/// launch — including when automatic checking is off, which is the default.
///
/// `CommandGroup(after: .appInfo)` inserts a **new** group behind the app-info
/// group rather than substituting its content. `AboutCommands` already uses
/// `replacing:` to own the About item; a second `replacing:` here would displace
/// it and the About window would lose its only entry point. The two compose in
/// this arrangement and in no other.
struct CheckForUpdatesCommands: Commands {
    /// The seam, never the concrete checker: a UI-test launch injects an
    /// in-memory updater here and can therefore never reach the network.
    let updater: any AppUpdating

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            // The rule lives in `Updates`; this only applies the answer. The
            // command goes dark solely while a check genuinely cannot run —
            // never because automatic checking is off, never because the last
            // check found nothing, never because the app has never checked.
            .disabled(!UpdateCommandEnablement.isEnabled(canCheckForUpdates: updater.canCheckForUpdates))
        }
    }
}
