import BrewProcess
import Catalog
import Foundation
import Observation

/// Why an import could not produce a document.
///
/// Two cases, and both of them are *whole-file* problems. Everything a line can
/// be wrong about is a counted skip inside a perfectly good document, which is
/// why there is no `.malformed` here (`brewfile-management` BF4).
public enum BrewfileImportError: Error, Sendable, Equatable {
    case unreadable(URL)
    case tooLarge(bytes: Int, limit: Int)
}

/// Why an export could not finish.
///
/// The dump's own typed failure is carried whole rather than flattened, so both
/// raw streams survive to the surface. A publication failure names the
/// destination it could not write, because "it failed" without saying where is
/// not something a user can act on.
public enum BrewfileExportError: Error, Sendable, Equatable {
    case dumpFailed(BundleDumpError)
    case publicationFailed(destination: URL, reason: String)
}

/// A Brewfile-scoped note about something an apply could not do.
///
/// `SystemProcess` sets `standardInput = .nullDevice`, so a cask that needs an
/// administrator password fails **opaquely** — brew asks, nothing answers, and
/// the run exits non-zero. Widening `MutationCommand`'s outcome vocabulary to
/// name that would change every install path in the app; deriving it here
/// changes only the surface that imported the file (design DD6).
///
/// Prompting for a password remains a stated non-goal. This tells the user what
/// happened and what to do instead, and nothing more.
public struct BrewfileApplyAdvisory: Sendable, Equatable, Identifiable {
    public let packageID: PackageID

    public init(packageID: PackageID) {
        self.packageID = packageID
    }

    public var id: PackageID { packageID }

    /// Named copy rather than view text, so the wording is assertable in the
    /// `swift test` inner loop and reviewable in one place.
    public var message: String {
        "\(packageID.name) needs an administrator password to install. "
            + "Cellar cannot supply one, so install it from Terminal with "
            + "`brew install --cask \(packageID.name)`."
    }
}

/// What the import and export surfaces read.
///
/// `@MainActor @Observable`, with `private(set)` state and two closed enums —
/// the `ServicesLoadState` / `InstalledLoadState` idiom. No state is an empty
/// value, a `nil`, or a never-settling pending case, so "the file said
/// nothing", "you already have all of it" and "we could not read it" are three
/// different screens rather than one blank list (design DD5).
///
/// It owns no concurrency of its own: the parser and the dump source are
/// `nonisolated`, and this class awaits their results and assigns them. No new
/// actor, no `nonisolated(unsafe)`, no `#available`.
@MainActor
@Observable
public final class BrewfileStore {

    public enum ImportState: Sendable, Equatable {
        case idle
        case reading
        case parsed(BrewfileDiff)
        case failed(BrewfileImportError)
    }

    public enum ExportState: Sendable, Equatable {
        case idle
        case dumping
        /// The dump's bytes, before any destination has been chosen.
        case preview(Data)
        case published(URL)
        case failed(BrewfileExportError)
    }

    public private(set) var importState: ImportState = .idle
    public private(set) var exportState: ExportState = .idle
    /// Notes about entries an apply could not complete. Empty until one occurs.
    public private(set) var advisories: [BrewfileApplyAdvisory] = []

    @ObservationIgnored private let fileSystem: any CatalogFileSystem

    public init(fileSystem: any CatalogFileSystem = DefaultCatalogFileSystem()) {
        self.fileSystem = fileSystem
    }

    // MARK: - Import

    /// The projection, when there is one. `nil` in every other state — never an
    /// empty diff standing in for "not asked yet".
    public var diff: BrewfileDiff? {
        guard case .parsed(let diff) = importState else { return nil }
        return diff
    }

    /// What a submission would run. `nil` until a file has been read.
    public var plan: BrewfilePlan? {
        diff.map { BrewfilePlan(selecting: $0.selectedEntries) }
    }

    /// Whether the import affordance does anything.
    ///
    /// Driven by the **selection**, never by the skip count: a file that
    /// produced skips is importable on exactly the same terms as one that did
    /// not (`brewfile-management` BF4, confirmed decision 3).
    public var canImport: Bool {
        guard let plan else { return false }
        return plan.isEmpty == false
    }

    /// Reads a file the user chose, and projects it against the inventories the
    /// caller is already holding.
    ///
    /// Cancelling the choice returns the store to `.idle`. That is an ordinary
    /// answer, not a failure: nothing went wrong and nothing was asked for.
    public func importFile(
        from chooser: some BrewfileSourceChoosing,
        installed: InstalledInventory,
        taps: TapInventory
    ) async {
        guard let url = await chooser.chooseSource() else {
            importState = .idle
            return
        }
        await importFile(at: url, installed: installed, taps: taps)
    }

    /// The same, for a URL already in hand.
    public func importFile(
        at url: URL,
        installed: InstalledInventory,
        taps: TapInventory
    ) async {
        importState = .reading

        let data: Data
        do {
            data = try fileSystem.contentsMappedIfSafe(of: url)
        } catch {
            importState = .failed(.unreadable(url))
            return
        }

        do {
            // Bytes in, a document out. Nothing here evaluates anything, and
            // nothing spawns (BF1, BF2).
            let document = try await BrewfileParser.decode(data)
            importState = .parsed(
                BrewfileDiff(document: document, installed: installed, taps: taps)
            )
        } catch {
            switch error {
            case .tooLarge(let bytes, let limit):
                importState = .failed(.tooLarge(bytes: bytes, limit: limit))
            }
        }
    }

    // MARK: - Selection

    /// Every mutation goes through the diff's own gate, so a present or skipped
    /// row cannot enter the selection by way of the store either.
    public func select(_ id: BrewfileEntry.ID) { mutateDiff { $0.select(id) } }
    public func deselect(_ id: BrewfileEntry.ID) { mutateDiff { $0.deselect(id) } }
    public func toggle(_ id: BrewfileEntry.ID) { mutateDiff { $0.toggle(id) } }
    public func selectAllMissing() { mutateDiff { $0.selectAllMissing() } }
    public func deselectAll() { mutateDiff { $0.deselectAll() } }

    private func mutateDiff(_ change: (inout BrewfileDiff) -> Void) {
        guard case .parsed(var diff) = importState else { return }
        change(&diff)
        importState = .parsed(diff)
    }

    // MARK: - Export

    /// The bytes a preview is showing, when one is. `nil` in every other state.
    public var previewDocument: Data? {
        guard case .preview(let document) = exportState else { return nil }
        return document
    }

    /// Runs the dump and settles on a preview.
    ///
    /// The destination panel is deliberately **not** opened here. It opens only
    /// after this succeeds, which is what makes a dump failure incapable of
    /// reaching the user's disk (design DD3).
    public func export(
        using source: some BundleDumpSourcing,
        detection: BrewDetectionState
    ) async {
        exportState = .dumping
        do {
            let result = try await source.dump(for: detection)
            exportState = .preview(result.document)
        } catch {
            exportState = .failed(.dumpFailed(error))
        }
    }

    /// Writes the previewed bytes to the destination the user chooses for
    /// **this** export.
    ///
    /// Does nothing at all unless there is a preview: publishing from a failed
    /// export must not write, and cancelling the choice keeps the preview so
    /// the user can pick again without re-running the dump.
    public func publish(to chooser: some BrewfileDestinationChoosing) async {
        guard let document = previewDocument else { return }
        guard let destination = await chooser.chooseDestination() else { return }

        do {
            try BrewfilePublication.publish(document, to: destination, using: fileSystem)
            exportState = .published(destination)
        } catch {
            exportState = .failed(
                .publicationFailed(
                    destination: destination,
                    reason: (error as NSError).localizedDescription
                )
            )
            // The preview is kept so the user can retry against another
            // destination without paying for a second dump.
            previewAfterFailure = document
        }
    }

    /// Held across a publication failure so the preview survives it.
    @ObservationIgnored private var previewAfterFailure: Data?

    // MARK: - DD6 — advisories

    /// Records an advisory when a terminal item says the run needed privileges
    /// Cellar will not acquire.
    ///
    /// Reads only the item's **already-decided** outcome and its package
    /// identity. It does not re-read the log, does not re-decide anything, and
    /// adds no case to the shipped outcome vocabulary.
    public func noteTerminal(_ item: ActivityItem) {
        guard item.outcome == .needsPrivileges, let packageID = item.packageID else { return }
        let advisory = BrewfileApplyAdvisory(packageID: packageID)
        guard advisories.contains(advisory) == false else { return }
        advisories.append(advisory)
    }

    public func clearAdvisories() {
        advisories = []
    }
}

extension BrewfileStore {
    /// The preview a failed publication kept, for a surface that wants to offer
    /// "try another location" without re-running the dump.
    public var retryableDocument: Data? {
        previewDocument ?? previewAfterFailure
    }
}
