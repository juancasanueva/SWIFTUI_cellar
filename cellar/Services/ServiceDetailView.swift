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
    /// The five verbs submit through the same guarded path everything else
    /// uses; this pane is where they moved when the list rows went compact.
    let operations: OperationCenter
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
            VStack(alignment: .leading, spacing: 22) {
                header(for: detail)
                controls(for: detail)
                facts(for: detail)
                logs(for: detail)
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 34, trailing: 30))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
    }

    /// The package detail's identity row, in service terms: name, then the
    /// status chip beside what it runs as.
    private func header(for detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(detail.name)
                .font(.system(size: 23, weight: .semibold))
                .kerning(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            HStack(spacing: 9) {
                ServiceStatusTag(status: detail.status)
                if let user = detail.user {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                    Text("runs as \(user)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// The five verbs, where their labels have the width the list rows never
    /// could give them.
    @ViewBuilder
    private func controls(for detail: ServiceDetail) -> some View {
        if let record = services.services.first(where: { $0.name == detail.name }) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Actions")
                ServiceControls(service: record, operations: operations)
            }
        }
    }

    @ViewBuilder
    private func facts(for detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Details")
            if let pid = detail.pid {
                fact("Process", String(pid))
            }
            if let plist = detail.plistPath {
                fact("Property list", plist.path)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.34))
            Text(value)
                .font(Theme.mono(12))
                .foregroundStyle(Color.white.opacity(0.72))
                .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Logs")
            if detail.logPaths.isEmpty {
                Text("This service declares no log location.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
            } else {
                ForEach(detail.logPaths, id: \.self) { url in
                    HStack(spacing: 8) {
                        Text(url.path)
                            .font(Theme.mono(12))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button("Open in Console") { opener.open(url) }
                            .buttonStyle(ActionPillStyle())
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
    ServiceDetailView(
        services: ServicesStore(),
        operations: OperationCenter(),
        opener: NoLogFileOpening()
    )
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
