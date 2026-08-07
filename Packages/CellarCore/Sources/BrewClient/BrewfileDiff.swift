import Catalog
import Foundation

/// What an imported Brewfile means for **this** machine.
///
/// A pure fold over two values the caller is already holding. It spawns no
/// process, issues no network request and forces no re-snapshot: the preview
/// costs zero new acquisition, exactly as `installed-inventory` and
/// `package-discovery` already require of their own projections
/// (`brewfile-management` BF6, design D1).
///
/// Selection lives here rather than in a view. "Can this row be selected" is a
/// fact about the row's typed state, so a surface cannot offer a checkbox for
/// something already installed, and no path — not even a wholesale assignment —
/// can move a present or skipped row into the selection.
public struct BrewfileDiff: Sendable, Hashable {

    /// The sentence a surface must show above the list.
    ///
    /// A named constant, so "this is Cellar's reading and not brew's verdict" is
    /// assertable in the inner loop rather than reviewed by eye. Nothing here
    /// asked Homebrew anything, and the projection must not imply otherwise.
    public static let attribution = "Cellar's reading of this file. Homebrew was not asked."

    /// Exactly three, and never a fourth.
    public enum State: Sendable, Hashable {
        /// Not installed here. Defaults to **selected**.
        case missing
        /// Already installed, or a tap already added. Visible, not selectable.
        case present
        /// The grammar refused the line. Visible with its reason, not selectable.
        case skipped
    }

    /// One line of the file, as this machine reads it.
    ///
    /// A single row type covering all three states, so "every parsed line
    /// projects into exactly one of three typed states" is the shape of the
    /// value rather than a claim about three parallel arrays — and so the rows
    /// can be rendered in file order with skips in place.
    public enum Row: Sendable, Hashable, Identifiable {
        case missing(BrewfileEntry)
        case present(BrewfileEntry)
        case skipped(BrewfileSkip)

        public var id: Int { lineNumber }

        public var lineNumber: Int {
            switch self {
            case .missing(let entry), .present(let entry): entry.lineNumber
            case .skipped(let skip): skip.lineNumber
            }
        }

        public var state: State {
            switch self {
            case .missing: .missing
            case .present: .present
            case .skipped: .skipped
            }
        }

        /// Only a missing entry. This is the whole selectability rule.
        public var isSelectable: Bool { state == .missing }

        public var entry: BrewfileEntry? {
            switch self {
            case .missing(let entry), .present(let entry): entry
            case .skipped: nil
            }
        }

        public var skip: BrewfileSkip? {
            guard case .skipped(let skip) = self else { return nil }
            return skip
        }
    }

    /// What kind of nothing, when there is nothing to do.
    ///
    /// Four distinct values rather than one empty list, because "the file said
    /// nothing", "you already have all of it" and "none of it is something
    /// Cellar installs" are three different things to tell a user, and
    /// collapsing them into "nothing to do" tells them none of it.
    public enum Summary: Sendable, Hashable {
        case nothingInTheFile
        case everythingAlreadyPresent
        case everythingSkipped
        case actionable
    }

    /// Every line, in file order.
    public let rows: [Row]
    /// The selection, always a subset of the missing rows' ids.
    public private(set) var selection: Set<BrewfileEntry.ID>

    private let selectableIDs: Set<BrewfileEntry.ID>

    public init(document: BrewfileDocument, installed: InstalledInventory, taps: TapInventory) {
        let tapNames = Set(taps.taps.map(\.name))

        var rows: [Row] = document.entries.map { entry in
            Self.isPresent(entry, installed: installed, tapNames: tapNames)
                ? .present(entry)
                : .missing(entry)
        }
        rows.append(contentsOf: document.skips.map(Row.skipped))
        rows.sort { $0.lineNumber < $1.lineNumber }

        self.rows = rows
        selectableIDs = Set(rows.filter(\.isSelectable).map(\.id))
        // Missing entries arrive selected. Present and skipped ones cannot.
        selection = selectableIDs
    }

    /// Membership only — the resident snapshots answer this, and nothing else
    /// is consulted.
    private static func isPresent(
        _ entry: BrewfileEntry,
        installed: InstalledInventory,
        tapNames: Set<String>
    ) -> Bool {
        switch entry.kind {
        case .tap(let tap, _): tapNames.contains(tap.rawValue)
        case .formula(let formula): installed.installedIDs.contains(formula.id)
        case .cask(let cask): installed.installedIDs.contains(cask.id)
        }
    }

    // MARK: - Projections

    public var missing: [BrewfileEntry] { rows.compactMap { $0.state == .missing ? $0.entry : nil } }
    public var present: [BrewfileEntry] { rows.compactMap { $0.state == .present ? $0.entry : nil } }
    public var skips: [BrewfileSkip] { rows.compactMap(\.skip) }

    /// The entries a submission would act on, in file order.
    public var selectedEntries: [BrewfileEntry] {
        rows.compactMap { row in
            guard row.isSelectable, selection.contains(row.id) else { return nil }
            return row.entry
        }
    }

    public var summary: Summary {
        if rows.isEmpty { return .nothingInTheFile }
        if selectableIDs.isEmpty == false { return .actionable }
        return skips.count == rows.count ? .everythingSkipped : .everythingAlreadyPresent
    }

    /// How many lines each reason accounted for.
    public var skipCounts: [BrewfileSkipReason.Category: Int] {
        skips.reduce(into: [:]) { counts, skip in
            counts[skip.reason.category, default: 0] += 1
        }
    }

    // MARK: - Selection

    /// Ignored unless `id` names a missing row. There is deliberately no
    /// unchecked path: this is the only way in.
    public mutating func select(_ id: BrewfileEntry.ID) {
        guard selectableIDs.contains(id) else { return }
        selection.insert(id)
    }

    public mutating func deselect(_ id: BrewfileEntry.ID) {
        selection.remove(id)
    }

    public mutating func toggle(_ id: BrewfileEntry.ID) {
        selection.contains(id) ? deselect(id) : select(id)
    }

    /// Filtered on exactly the same rule, so replacing the set wholesale is not
    /// a way around the per-id gate.
    public mutating func setSelection(_ ids: Set<BrewfileEntry.ID>) {
        selection = ids.intersection(selectableIDs)
    }

    public mutating func selectAllMissing() {
        selection = selectableIDs
    }

    public mutating func deselectAll() {
        selection = []
    }
}
