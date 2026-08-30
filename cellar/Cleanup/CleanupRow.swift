import AppKit
import BrewClient
import Catalog
import DiskUsage
import SwiftUI

/// One package's storage, behind a hand-built disclosure.
///
/// **Why not `DisclosureGroup`.** The native control cannot host this row: kept
/// top-level it renders its triangle but merges the whole label into one
/// element, so the cleanup pills inside it stop existing to accessibility and
/// to clicks; wrapped in a stack beside the pills it renders no triangle at
/// all. `ArtifactIntegritySection.signingIdentity` hit the same wall and
/// documents the same exit: a `Button` whose label spans the row, a chevron
/// this file draws and rotates, and expansion state the row owns.
struct CleanupRow: View {
    let package: DiskPackageUsage
    /// The roots the snapshot was measured against, for the on-disk path of
    /// each version. Optional so a row can render without a snapshot; then
    /// the versions simply carry no path.
    var roots: DiskRootsIdentity?
    /// Trailing row content — the per-package cleanup pills.
    var accessory: AnyView = AnyView(EmptyView())
    /// Rendered above the versions when expanded — the preview state's own
    /// sentences and evidence.
    var detailHeader: AnyView = AnyView(EmptyView())
    /// Flips to `true` when `detailHeader` has something worth seeing — a
    /// preview loading, or its outcome. The row opens itself on that edge, so
    /// a Preview click never lands its answer behind a closed chevron. It
    /// never closes the row: that stays the user's.
    var revealsDetail: Bool = false

    @State private var isExpanded = false
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        HStack(spacing: 6) {
                            Text(package.id.name)
                            kindPill
                        }
                        Spacer(minLength: 0)
                        Text(onDisk(package.observation.allocatedBytes))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("disk-package-\(package.id.kind.rawValue)-\(package.id.name)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Hides the versions on disk" : "Shows the versions on disk")
                accessory
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    detailHeader
                    ForEach(package.versions) { version in
                        HStack(spacing: 10) {
                            Text(version.id.rawVersion)
                            if let location = roots?.location(of: version) {
                                revealButton(location, for: version)
                            }
                            Spacer()
                            Text(onDisk(version.observation.allocatedBytes))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier(
                            "disk-version-\(package.id.kind.rawValue)-\(package.id.name)-\(version.id.rawVersion)"
                        )
                    }
                }
                .padding(.leading, 18)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: revealsDetail) { _, reveals in
            if reveals { isExpanded = true }
        }
    }

    /// Which pill sits beside the name.
    ///
    /// Elsewhere a formula is the unmarked case: `PackageKindTag` returns `nil`
    /// for it, because in the Installed list formulae are the silent majority
    /// and tagging every one would be noise. This list is different — npm
    /// globals and formulae share it in similar numbers, sorted by size rather
    /// than kind — so an unmarked row here reads as "unknown", not "formula".
    /// The formula pill is therefore this list's own; casks and npm still defer
    /// to the shared tag so the three surfaces cannot disagree about *those*.
    nonisolated enum KindPill: Equatable, Sendable {
        case formula
        case shared(PackageKindTag)
    }

    nonisolated static func kindPill(for kind: PackageKind) -> KindPill {
        if let tag = PackageKindTag(kind: kind) { return .shared(tag) }
        return .formula
    }

    @ViewBuilder
    private var kindPill: some View {
        switch Self.kindPill(for: package.id.kind) {
        case .shared:
            KindTag(kind: package.id.kind)
        case .formula:
            Text("FORMULA")
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                // Green is the one semantic tint the other two pills leave
                // free: npm is info-blue and casks are purple.
                .background(
                    Theme.successTint(0.18),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .foregroundStyle(Theme.successText)
                .accessibilityLabel("Formula")
                .accessibilityIdentifier("kind-tag-formula")
        }
    }

    /// The path, and the one thing to do with it: show it in Finder. Local to
    /// the row on purpose — it belongs to a directory on screen, not to a
    /// package, so it has no place in the shared package menus.
    private func revealButton(_ location: URL, for version: DiskVersionUsage) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([location])
        } label: {
            // Styled as the app's links are (the tap repository link in
            // `TapDetailView`): accent-coloured mono, with the pointer hand so
            // a path reads as somewhere to go rather than a label.
            Text(location.path)
                .font(Theme.mono(11))
                .foregroundStyle(theme.base)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal \(location.path) in Finder")
        .accessibilityIdentifier(
            "disk-version-path-\(package.id.kind.rawValue)-\(package.id.name)-\(version.id.rawVersion)"
        )
    }

    private func onDisk(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file)) + " on disk"
    }
}
