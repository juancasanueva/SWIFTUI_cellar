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
        } else {
            // Which of the four outcomes this is — nothing selected, reading,
            // answered, failed — is decided by `ServiceDetailLoadState.pane` in
            // `BrewClient`, inside the `swift test` inner loop. Branching here
            // on `detail != nil` alone is what reported a **failed** probe as
            // "No service selected", with brew's reason discarded.
            switch services.detailState.pane {
            case .detail(let detail):
                content(for: detail)
            case .notice(let notice):
                ServiceDetailNoticeView(notice: notice)
            }
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

/// Why the detail pane has no detail — which is never the same reason twice.
///
/// `ServicesEmptyStateView`'s shape, one pane over: nothing selected, a probe
/// still in flight, and a probe that failed are three different facts, and
/// rendering the last two as the first tells the user that they simply have not
/// picked anything — when in truth brew was asked and could not answer.
///
/// The words and the mapping both live in `ServicesPresentation`; this view owns
/// only the symbols and the layout.
private struct ServiceDetailNoticeView: View {
    let notice: ServiceDetailNotice

    var body: some View {
        ContentUnavailableView(
            notice.title,
            systemImage: symbol,
            description: Text(notice.message)
        )
    }

    /// Only a failure gets the warning symbol. An unanswered probe has not
    /// failed, and nothing having been selected is not a problem at all.
    private var symbol: String {
        switch notice {
        case .nothingSelected, .reading: AppSection.services.systemImage
        case .failed: "exclamationmark.triangle"
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

#Preview("Nothing selected") {
    ServiceDetailNoticeView(notice: .nothingSelected)
}

#Preview("Reading") {
    ServiceDetailNoticeView(notice: .reading("atuin"))
}

#Preview("Failed") {
    ServiceDetailNoticeView(
        notice: .failed(
            service: "atuin",
            reason: ServiceDetailFailure.probe(.malformedPayload).shortDescription
        )
    )
}
