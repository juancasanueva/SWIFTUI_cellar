//
//  ServiceDetailView.swift
//  cellar
//

import AppKit
import BrewClient
import SwiftUI

/// What brew knows about the selected service.
///
/// Everything here comes from one `brew services info --json <name>` run, made
/// lazily when the selection changed — never on a poll tick.
struct ServiceDetailView: View {
    let services: ServicesStore
    /// The seam. `BrewClient` owns the protocol; this target owns the single
    /// `NSWorkspace` implementation.
    var opener: any LogFileOpening = WorkspaceLogFileOpener()

    var body: some View {
        if let absence = services.absence {
            // Read-only guidance, not an error state, and not a new rule: the
            // same absence the rest of the app renders.
            ContentUnavailableView {
                Label(absence.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(absence.explanation)
            }
        } else if let detail = services.detail {
            content(for: detail)
        } else {
            ContentUnavailableView(
                "No service selected",
                systemImage: AppSection.services.systemImage,
                description: Text("Select a service to see where it is installed and what it logs.")
            )
        }
    }

    private func content(for detail: ServiceDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(for: detail)
                Divider()
                facts(for: detail)
                Divider()
                logs(for: detail)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(for detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.name)
                .font(.title2)
                .textSelection(.enabled)
            ServiceStatusTag(status: detail.status)
        }
    }

    @ViewBuilder
    private func facts(for detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let user = detail.user {
                LabeledContent("User", value: user)
            }
            if let pid = detail.pid {
                LabeledContent("Process", value: String(pid))
            }
            if let plist = detail.plistPath {
                LabeledContent("Property list") {
                    Text(plist.path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// The deduped log locations.
    ///
    /// `logPaths` is already one entry per **file**, so a service whose log and
    /// error log are the same file — which is the live shape on this machine —
    /// offers one button rather than two that open the same window. A service
    /// declaring none says so, and shows no empty or placeholder path.
    @ViewBuilder
    private func logs(for detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logs")
                .font(.headline)
            if detail.logPaths.isEmpty {
                Text("This service declares no log location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.logPaths, id: \.self) { url in
                    HStack(spacing: 8) {
                        Text(url.path)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button("Open in Console") { opener.open(url) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

/// The one place AppKit opens a file. Kept behind `LogFileOpening` so every
/// rule above it stays provable without a window.
struct WorkspaceLogFileOpener: LogFileOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    ServiceDetailView(services: ServicesStore(), opener: NoLogFileOpening())
}
