//
//  PackageDetailView+Receipt.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// The detail an installed package gets when the catalog does not carry it
/// (installed-inventory II15).
///
/// A second file rather than a second view: the identity row, the fact rows and
/// the two store-derived facts are the ones the catalog pane already renders, so
/// this extension **calls** them and duplicates none. That is the whole reason
/// those helpers are internal — Swift `private` is file-scoped, and a second
/// copy of any of them would be exactly the drift the one-projection rule exists
/// to prevent (design DD-9).
///
/// Nothing here acquires anything. The receipt is already resident, the three
/// stores it reads are already wired, and the value is built synchronously in
/// `body` — the same idiom the shipped `versionStory` and `installedAs` use
/// (design DD-10).
extension PackageDetailView {

    /// The header, the receipt's own facts, the private note, the scoped
    /// sentence about Cellar's catalog, and — last, where the catalog pane puts
    /// it — the shared Actions section.
    @ViewBuilder
    func uncatalogedContent(for snapshot: InstalledPackage) -> some View {
        let detail = InstalledDetailProjection(snapshot)
        VStack(spacing: 0) {
            header(
                id: snapshot.id,
                displayName: snapshot.displayName,
                versionStory: versionStory(installed: snapshot),
                installed: snapshot
            ) {
                // Deliberately empty. This pane's verbs live in the shared
                // Actions section at the foot of it, exactly where the catalog
                // pane puts them, so there is one place to act rather than two
                // (installed-inventory II15, design DD-24).
                EmptyView()
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 0, trailing: 30))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    receiptDescription(detail)
                    receiptFacts(detail, for: snapshot)
                    PackageMetadataSection(entry: receiptEntry(for: snapshot), metadata: metadata)
                    receiptFooter
                    // The catalog pane's own Actions section, called rather than
                    // copied: the verbs, their applicability, the confirmation
                    // rule, the argv and the command line all arrive already
                    // proven, and there is exactly one declaration of them.
                    actionsSection(for: receiptEntry(for: snapshot))
                }
                .padding(EdgeInsets(top: 22, leading: 30, bottom: 34, trailing: 30))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle(snapshot.displayName)
    }

    /// The entry every shared surface on this pane takes.
    ///
    /// `catalog: nil` is the honest shape: there is no record, and
    /// `PackageEntry` has said so since the Installed list shipped, so neither
    /// the menu nor the note needs a new type to reach this pane.
    private func receiptEntry(for snapshot: InstalledPackage) -> PackageEntry {
        PackageEntry(installed: snapshot, catalog: nil, id: snapshot.id)
    }

    /// The published description as its own block, exactly as the catalog pane
    /// renders it. Absent means absent: no block, no empty well.
    @ViewBuilder
    private func receiptDescription(_ detail: InstalledDetailProjection) -> some View {
        if let published = detail.description {
            VStack(alignment: .leading, spacing: 7) {
                SectionHeader("Description")
                Text(published)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(maxWidth: 680, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    /// The fact grid, in II15's group order: identity, then origin, then install
    /// state.
    ///
    /// The order and the copy are the projection's; this only draws them.
    @ViewBuilder
    private func receiptFacts(
        _ detail: InstalledDetailProjection,
        for snapshot: InstalledPackage
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 26, alignment: .topLeading),
                    count: 3
                ),
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(detail.identity, id: \.self) { item in
                    receiptFact(item)
                }
                // The grant is a fact *about this origin*, so it is joined here
                // beside the tap it belongs to — under the very guard that
                // produced the fact, so a receipt whose tap Homebrew withholds
                // yields neither the row nor the marker (PD8, PT3).
                if let tap = snapshot.tap, let origin = detail.tapOfOrigin {
                    receiptFact(origin, note: marker(for: snapshot.id, publishedBy: tap))
                }
                ForEach(detail.installStateFacts, id: \.self) { item in
                    receiptFact(item)
                }
                // Two install-state facts other capabilities already own for
                // this same identity. They stay view-side because both answers
                // change between renders, which is exactly what a `Hashable`
                // value must not carry (design DD-7).
                if let installedAs = installedAs(for: snapshot.id) {
                    fact("Installed as", installedAs)
                }
                if let size = sizeOnDisk(for: snapshot.id) {
                    fact("Size on disk", size.formatted(.byteCount(style: .file)), mono: true)
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    /// One projected fact, drawn by the shared helper its style names.
    @ViewBuilder
    private func receiptFact(
        _ item: InstalledDetailProjection.Fact,
        note: String? = nil
    ) -> some View {
        switch item.style {
        case .plain:
            fact(item.label, item.value, note: note)
        case .mono:
            fact(item.label, item.value, mono: true, note: note)
        case .link(let url):
            factLink(item.label, url)
        }
    }

    /// The marker, or `nil`.
    ///
    /// Resolved by exact identity through the one projection that owns the copy,
    /// so this surface composes none of its own. Positive-only: a package with
    /// no recorded grant carries no badge, no muted marker and no note, because
    /// absence from the report is not a fact about the package (PT5, PT6).
    private func marker(for id: PackageID, publishedBy tap: String) -> String? {
        TapProjection.grantsIndividually(id, publishedBy: tap, in: trustGrants.grants)
            ? TapProjection.grantMarker
            : nil
    }

    /// The scoped sentence, byte-unchanged from the one this pane used to show
    /// as its whole body — now a footer beneath the facts rather than an empty
    /// state standing in for them.
    ///
    /// A catalog miss has several causes, so the sentence stays a statement
    /// about Cellar's catalog and makes no claim about the package's origin
    /// (design DD-12).
    private var receiptFooter: some View {
        Text("This installed package is not in Cellar’s core/cask catalog.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
