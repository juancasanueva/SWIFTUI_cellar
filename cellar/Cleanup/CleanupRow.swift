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
    /// Trailing row content — the per-package cleanup pills.
    var accessory: AnyView = AnyView(EmptyView())
    /// Rendered above the versions when expanded — the preview state's own
    /// sentences and evidence.
    var detailHeader: AnyView = AnyView(EmptyView())

    @State private var isExpanded = false

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
                        VStack(alignment: .leading) {
                            Text(package.id.name)
                            Text(package.id.kind == .formula ? "Formula" : "Cask")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                        HStack {
                            Text(version.id.rawVersion)
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
    }

    private func onDisk(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file)) + " on disk"
    }
}
