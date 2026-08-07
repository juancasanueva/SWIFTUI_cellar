import Catalog
import Foundation

/// Where a file comes from, and where it goes.
///
/// Declared here and conformed in the app target, so `CellarCore` imports no
/// AppKit and the store stays testable without a window server. They return a
/// **plain `URL?`** and nothing else: `fileExporter` would perform the write
/// itself, which would take publication away from `CatalogFileSystem` and
/// dissolve the atomicity this capability requires (design DD4).
///
/// `nil` means the user cancelled. That is an ordinary answer, not an error:
/// cancelling publishes nothing, and the export's temporary file is removed
/// regardless, because its lifecycle belongs to the dump rather than to a panel.
public protocol BrewfileDestinationChoosing: Sendable {
    func chooseDestination() async -> URL?
}

public protocol BrewfileSourceChoosing: Sendable {
    func chooseSource() async -> URL?
}

/// Cellar's own write of the dump's bytes to the destination the user chose for
/// **this** export (`brewfile-management` BF9).
///
/// Deliberately one function with no state. Three things follow from that:
///
/// - **The bytes are the document's bytes.** There is nowhere to reformat,
///   re-encode, reorder, filter or append provenance, because nothing here
///   looks at the contents at all.
/// - **Nothing is remembered.** No `UserDefaults` key, no `@AppStorage`, no
///   security-scoped bookmark, no last-used path. A destination is an argument,
///   not a stored property, so a second export cannot reuse the first one's.
/// - **No well-known location is reachable.** `~/.Brewfile`,
///   `~/.homebrew/Brewfile`, an XDG config path and
///   `$HOMEBREW_BUNDLE_FILE_GLOBAL` are not named anywhere here, so the only
///   way to write to one is for the user to have chosen exactly that path.
///
/// Atomicity is the shipped seam's, reused unwidened: `CatalogFileSystem.write`
/// is `Data.write(to:options: .atomic)`, so a failed publication leaves a
/// pre-existing file exactly as it was and never a partial one beside it.
public enum BrewfilePublication {
    public static func publish(
        _ document: Data,
        to destination: URL,
        using fileSystem: some CatalogFileSystem
    ) throws {
        try fileSystem.write(document, to: destination)
    }
}
