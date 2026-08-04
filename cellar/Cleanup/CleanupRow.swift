import Catalog
import DiskUsage
import SwiftUI

struct CleanupRow: View {
    let package: DiskPackageUsage

    var body: some View {
        DisclosureGroup {
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
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(package.id.name)
                    Text(package.id.kind == .formula ? "Formula" : "Cask")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(onDisk(package.observation.allocatedBytes))
            }
        }
        .accessibilityIdentifier("disk-package-\(package.id.kind.rawValue)-\(package.id.name)")
    }

    private func onDisk(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file)) + " on disk"
    }
}
