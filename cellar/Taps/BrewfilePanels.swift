//
//  BrewfilePanels.swift
//  cellar
//

import AppKit
import BrewClient
import Foundation

/// The two AppKit seams `CellarCore` declares and this target conforms.
///
/// `BrewfileSourceChoosing` and `BrewfileDestinationChoosing` return a plain
/// `URL?` and nothing else. That is the whole of design DD4: `fileExporter` and
/// `fileImporter` would perform the write themselves, which would take
/// publication away from `CatalogFileSystem.write(_:to:)` and dissolve the
/// atomicity `brewfile-management` BF9 requires. Panels choose a path; Cellar
/// writes the bytes.
///
/// Both conformers are `nonisolated Sendable` structs that hop to `@MainActor`
/// internally, because the protocols are `Sendable` and the store awaiting them
/// is not the actor a panel must run on.
///
/// `nil` means the user cancelled. That is an ordinary answer rather than an
/// error: cancelling an import leaves the store idle, and cancelling a
/// destination publishes nothing while still removing the export's temporary
/// file.
///
/// ## A latent trap, recorded rather than fixed
///
/// The app's build settings carry `ENABLE_APP_SANDBOX = NO` and, beside it,
/// `ENABLE_USER_SELECTED_FILES = readonly`. The second value is **inert** today,
/// because the first one switches the entitlement machinery off entirely. It is
/// recorded here, next to the only code it could ever affect, because of the
/// shape of the failure it would cause: if the sandbox is ever enabled, a
/// `readonly` user-selected-files entitlement **permits the import's read** and
/// **blocks the export's write**. Half the feature would keep working, which is
/// the kind of breakage that reaches a bug report rather than a build failure.
///
/// The fix, if that day comes, is `ENABLE_USER_SELECTED_FILES = readwrite` — not
/// a security-scoped bookmark. Cellar does not want a *durable* grant to
/// anything: a destination is chosen per export and remembered nowhere, so a
/// bookmark would be a memory this capability is specified not to have.
enum BrewfilePanels {
    /// Shared by both panels so the two surfaces read as one feature.
    static let fileName = "Brewfile"
}

/// Where an import reads from.
struct BrewfileSourcePanel: BrewfileSourceChoosing {
    static let prompt = "Import"
    static let message = "Choose a Brewfile to read. Cellar reads it as text and runs nothing in it."

    /// Everything this panel is, as one function over a panel the caller owns.
    ///
    /// Separated from `chooseSource()` so the configuration is assertable
    /// without a window server: a test constructs a real `NSOpenPanel`, applies
    /// this, and reads it back.
    @MainActor
    static func configure(_ panel: NSOpenPanel) {
        panel.prompt = prompt
        panel.message = message
        panel.canChooseFiles = true
        // A directory is not a Brewfile, and an import reads exactly one file.
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        // Deliberately unfiltered. A Brewfile has no extension, so a content
        // type filter would grey out the very file the user came to pick.
        panel.allowedContentTypes = []
    }

    func chooseSource() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            Self.configure(panel)
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }
    }
}

/// Where an export writes to.
///
/// The panel is opened by the export sheet **only after** a successful preview,
/// so a failed dump can never reach the user's disk (design DD3). Nothing here
/// seeds a directory: no `~/.Brewfile`, no `~/.homebrew/Brewfile`, no XDG path
/// and no `$HOMEBREW_BUNDLE_FILE_GLOBAL`. The only way Cellar writes to one of
/// those is for the user to have navigated there for this export.
struct BrewfileDestinationPanel: BrewfileDestinationChoosing {
    static let prompt = "Export"
    static let message = "Choose where to save this Brewfile. Cellar writes the file itself, atomically."

    @MainActor
    static func configure(_ panel: NSSavePanel) {
        panel.prompt = prompt
        panel.message = message
        panel.nameFieldStringValue = BrewfilePanels.fileName
        panel.canCreateDirectories = true
        // A Brewfile has no extension, so there is none to hide and none to
        // enforce.
        panel.allowedContentTypes = []
        panel.isExtensionHidden = false
    }

    func chooseDestination() async -> URL? {
        await MainActor.run {
            let panel = NSSavePanel()
            Self.configure(panel)
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }
    }
}
