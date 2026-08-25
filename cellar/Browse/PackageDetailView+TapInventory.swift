//
//  PackageDetailView+TapInventory.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The detail a package gets when the catalog does not carry it, this Mac has
/// not installed it, and exactly one installed third-party tap publishes it
/// (`package-search` PS8 round 6).
///
/// A second extension file rather than a second view, on exactly the terms
/// `PackageDetailView+Receipt.swift` established: the identity row, the fact
/// rows and the mutation surface are the ones the catalog pane already renders,
/// so this **calls** them and duplicates none. That is what those helpers are
/// internal for.
///
/// ## What is deliberately not here
///
/// No description, no version, no homepage, no licence, no dependency list, no
/// analytics and no size on disk. The tap inventory publishes none of them, and
/// fetching any would need the tap-source read `tap-management` TM5 forbids
/// unconditionally — for this pane exactly as for every other consumer. An
/// installed package gets all of it from its receipt, one branch above. The
/// absence is presented **as** an absence: no placeholder, no dash, no empty
/// row (`package-detail` PD1).
///
/// No trust badge, no trust control and no grant marker either. PD8's marker is
/// a fact about a **receipt's** tap of origin, and a package this Mac has not
/// installed has no receipt for it to be a fact about (`package-mutation` PM10,
/// `tap-management` TM12).
///
/// No private-note section either, unlike the receipt pane. That one is not a
/// tap-published value and would have been defensible, but PS8 enumerates what
/// this pane presents and closes the list — so it is a product decision to make
/// deliberately, not one to inherit by mirroring a neighbouring file. The
/// favourite heart is the one affordance that does arrive anyway: it belongs to
/// the shared identity header this pane is required to reuse, and it writes to
/// the same store from every pane that draws it.
///
/// Nothing here acquires anything: the tap inventory is already resident from
/// the refresh `tap-management` performs, and the value is built synchronously
/// in `body` (design DD-21, DD-22).
extension PackageDetailView {

    /// The header, the two facts the inventory published, the install state, the
    /// sentence that says why there is no more, and — last, where the catalog
    /// pane puts it — the shared Actions section.
    @ViewBuilder
    func tapInventoryContent(for published: TapInventoryDetail) -> some View {
        VStack(spacing: 0) {
            header(
                id: published.id,
                displayName: published.displayName,
                // No version story at all — the tap publishes no version, so the
                // line and its separator are omitted rather than emptied.
                versionStory: nil,
                // No receipt: the header's own status badge reads the absence
                // and says so, exactly as it does for a catalog package this Mac
                // does not have.
                installed: nil
            ) {
                // Deliberately empty. The verbs live in the shared Actions
                // section at the foot of this pane, exactly where the catalog
                // pane puts them, so one pane offers one place to act
                // (package-search PS8 round 8, design DD-24).
                EmptyView()
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 0, trailing: 30))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    publishedFacts(published)
                    publishedFooter(published)
                    // The catalog pane's own Actions section, called rather than
                    // copied. It is handed no installed record — there is none —
                    // and no catalog record — there is none, and PD6 forbids
                    // synthesizing one — so it takes its install branch and
                    // offers Install over the bare token PM10 mandates.
                    actionsSection(for: publishedEntry(for: published))
                }
                .padding(EdgeInsets(top: 22, leading: 30, bottom: 34, trailing: 30))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle(published.displayName)
    }

    /// The entry every shared surface on this pane takes.
    ///
    /// Both records are `nil`, and both absences are load-bearing: there is no
    /// receipt, and a catalog record for a package the catalog does not cover is
    /// exactly what `package-detail` PD6 forbids — including one synthesized
    /// from a tap's published name.
    private func publishedEntry(for published: TapInventoryDetail) -> PackageEntry {
        PackageEntry(installed: nil, catalog: nil, id: published.id)
    }

    /// The two facts the inventory published, plus what this Mac says about
    /// having it.
    ///
    /// The same grid the receipt pane draws, through the same shared `fact`
    /// helper, so one fact reads one way on both panes. The install-state line
    /// is the **projection's** sentence — TM5's exact string — not one this file
    /// words (PS8's copy-ownership clause).
    @ViewBuilder
    private func publishedFacts(_ published: TapInventoryDetail) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 26, alignment: .topLeading),
                count: 3
            ),
            alignment: .leading,
            spacing: 16
        ) {
            fact("Type", published.kind == .formula ? "Formula" : "Cask")
            fact("Tap", published.tapName, mono: true)
            fact("Install state", published.stateCopy)
        }
        .frame(maxWidth: 820, alignment: .leading)
    }

    /// Why the pane stops here, said outright rather than left to be inferred
    /// from a short page.
    ///
    /// The sentence is the projection's, like every other sentence this change
    /// pins, so it is worded in exactly one place and a `unit` test can read its
    /// bytes. It makes a claim about **Cellar's knowledge**, never about the
    /// package or its tap.
    private func publishedFooter(_ published: TapInventoryDetail) -> some View {
        Text(published.footerCopy)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
