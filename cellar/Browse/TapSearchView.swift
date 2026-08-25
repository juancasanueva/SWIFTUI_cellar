//
//  TapSearchView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// Search our taps: the packages the taps this Mac has installed publish.
///
/// A visual sibling of `BrowseView` — the same search field, the same filter
/// bar, the same list, rows and install menu — over a different source. It is
/// its **own** surface rather than a section of the catalog list, so the
/// catalog query surface stays catalog-only and its file carries a zero-line
/// diff (`package-search` PS8, DD-8).
///
/// The surface composes **no copy of its own**. Every sentence it shows — the
/// withheld-tap note, the catalog collision and each empty state — is supplied
/// by `TapPackageSearch`, and the installed mark is the shared `StatusPill`
/// component the catalog rows draw, so two surfaces cannot word or draw the
/// same fact differently (PS8, DD-7, DD-9, DD-17, DD-18).
///
/// It also decides nothing. Which rows may be selected, which carry a collision
/// note, which identity the install names and why the list is empty are all
/// facts of the projection, resolved once there and only read here (DD-4, DD-6).
struct TapSearchView: View {
    /// The tap inventory this Mac already has resident, from the refresh
    /// `tap-management` performs. Read, never refreshed: composing this surface
    /// costs no brew invocation (PS8).
    let taps: TapStore
    let installed: InstalledStore
    /// Read for **membership alone** — whether the catalog carries a hit's bare
    /// token — and never for a hit's content (PD6).
    let catalog: CatalogStore
    let operations: OperationCenter
    /// The shell's one selection, threaded exactly as `BrowseView` threads it:
    /// a routable hit lands on the shared `PackageDetailView` through the
    /// existing resolution order, with no routing arm of its own here (DD-4).
    /// That order resolves the catalog, then this Mac's receipt, then the tap
    /// inventory — so an installed hit reaches the receipt pane and a
    /// not-installed one the name-only pane, both without this file deciding
    /// (DD-21).
    @Binding var selection: PackageID?

    @State private var query = ""
    @State private var filters = SearchFilters()
    @State private var hideInstalled = false

    var body: some View {
        // Composed once per render and read twice below, rather than
        // recomputed at each use. Built **synchronously in `body`**: both
        // inputs are already resident, so an async hop would only add a frame
        // where the list is empty for a value that was never absent (DD-12).
        let hits = self.hits

        VStack(spacing: 0) {
            VStack(spacing: 10) {
                PaneSearchField(
                    text: $query,
                    prompt: "Search \(packageCount.formatted()) packages…"
                )
                // The catalog's own bar, reused with its two unanswerable
                // groups switched off: a tap hit has no version to be outdated
                // and no published deprecation or disabled flag, so offering
                // either control would leave an enabled control inert (DD-15).
                CatalogFilterBar(
                    filters: $filters,
                    hideInstalled: $hideInstalled,
                    outdatedOnly: .constant(false),
                    isInstalledFilterEnabled: installed.absence == nil,
                    showsOutdatedChip: false,
                    showsCatalogPredicates: false
                )
            }
            .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
            HairlineDivider()

            List(selection: $selection) {
                ForEach(hits) { hit in
                    if let routable = hit.routableID {
                        row(hit)
                            .tag(routable)
                            .themedListSelection(isSelected: selection == routable)
                    } else {
                        // Deliberately inert, and for one reason only:
                        // **ambiguity**. Either the catalog carries this bare
                        // token and would answer for it instead, or two taps
                        // publish it and there is no single package to open —
                        // so a pane here would present something other than the
                        // row chosen. The install state decides nothing: since
                        // round 6 a not-installed hit routes too, to the
                        // name-only detail composed from this same inventory
                        // (PS8 round 6, DD-21).
                        row(hit)
                            .selectionDisabled()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if hits.isEmpty {
                    TapSearchEmptyState(presentation: presentation(hitCount: hits.count))
                }
            }
        }
        .background(Color.white.opacity(0.014))
    }

    private var packageCount: Int {
        TapPackageSearch.packageCount(inventory: taps.inventory)
    }

    /// The matching hits, composed above the catalog index and never pushed
    /// into it. An empty query lists everything the taps publish (DD-16).
    private var hits: [TapSearchHit] {
        TapPackageSearch(inventory: taps.inventory, installed: installed.inventory)
            .hits(
                query: query,
                kinds: filters.kinds,
                hideInstalled: hideInstalled,
                isInCatalog: { catalog.package($0) != nil }
            )
    }

    private func presentation(hitCount: Int) -> TapSearchPresentation {
        TapPackageSearch.presentation(
            tapState: taps.state,
            inventory: taps.inventory,
            query: query,
            hitCount: hitCount
        )
    }

    private func row(_ hit: TapSearchHit) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                    KindTag(kind: hit.id.kind)
                    if hit.isInstalled {
                        // The **same** component the catalog rows draw, in the
                        // same position after the kind chip, so one install
                        // state reads one way on both search surfaces. Its
                        // label belongs to that component: this file composes
                        // none of it (PS8, DD-18).
                        StatusPill.installed
                    }
                    // The **same** update chip the catalog rows, the Installed
                    // list and the Updates list draw — immediately after the
                    // installed pill, exactly where the catalog row puts it, so
                    // "this has an update" reads identically on both search
                    // surfaces. The offered version is handed over as a value:
                    // this file words nothing about it, and the fact itself is
                    // the projection's, gated on the receipt's own outdated
                    // rule (PS8 round 4, DD-19).
                    if let next = hit.nextVersion {
                        UpdateTag(nextVersion: next)
                    }
                    Spacer(minLength: 0)
                }
                Text(hit.tapName)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
                // Only what the pill cannot say: what Homebrew is withholding,
                // and which package a colliding token actually installs. A row
                // with neither is silent, exactly as a catalog row is.
                if let note = self.note(hit) {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            // The shared spine, unconditionally: the menu decides which verbs
            // this package can be offered, from the record below and the bare
            // token (package-mutation PM10).
            MutationMenu(center: operations, entry: entry(for: hit))
        }
        .padding(.vertical, 3)
    }

    /// The hit as the shared mutation spine takes it: **the record this Mac
    /// already holds** where the package is installed, no catalog record ever,
    /// and the bare token the projection resolved (PS8 round 5, DD-20).
    ///
    /// The record is the projection's — resolved there by the tap-aware handoff,
    /// so a colliding catalog package's receipt can never arrive here — and this
    /// file neither looks one up nor re-keys one. Handing it over is the whole
    /// change: `MutationMenu` already branches on it, and already words and
    /// orders Reinstall, Uninstall…, Upgrade and Pin for itself. `catalog` stays
    /// `nil` in **both** install states: no catalog record reaches this row
    /// (`package-detail` PD6).
    private func entry(for hit: TapSearchHit) -> PackageEntry {
        PackageEntry(installed: hit.installed, catalog: nil, id: hit.mutationTarget)
    }

    /// The row's explanatory line, or `nil` when the row has nothing to explain.
    ///
    /// Joined from values, never composed from words: both sentences come from
    /// the projection, and either may be absent.
    private func note(_ hit: TapSearchHit) -> String? {
        let sentences = [hit.stateNote, hit.collisionNote].compactMap(\.self)
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}

/// Why the list is empty, which is never the same reason twice.
///
/// A private sibling of `BrowseView`'s `EmptyResults` rather than a shared
/// type. **Forced, not chosen** (DD-10): `EmptyResults` is `private` and Swift
/// `private` is file-scoped, so any reuse — or any extraction to a third
/// file — would edit `BrowseView.swift`, which this change requires to be
/// byte-identical to its base revision. The two are not the same view either:
/// they answer different questions and share only their last case.
///
/// Every sentence here comes from the projection. This view composes none.
private struct TapSearchEmptyState: View {
    let presentation: TapSearchPresentation

    var body: some View {
        switch presentation {
        case .loading:
            ContentUnavailableView("Reading your taps", systemImage: "sparkle.magnifyingglass")
        case .unavailable, .failed, .noTaps:
            ContentUnavailableView(
                presentation.emptyStateCopy ?? "",
                systemImage: "sparkle.magnifyingglass"
            )
        case .noMatch(let query):
            ContentUnavailableView.search(text: query)
        case .content:
            EmptyView()
        }
    }
}

#Preview {
    @Previewable @State var selection: PackageID?
    return TapSearchView(
        taps: TapStore(),
        installed: InstalledStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        operations: OperationCenter(),
        selection: $selection
    )
}
