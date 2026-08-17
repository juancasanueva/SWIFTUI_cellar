//
//  ServiceDetailView.swift
//  cellar
//

import AppKit
import BrewClient
import SwiftUI

/// What brew knows about the expanded service — the card's lower half.
///
/// Everything here comes from one `brew services info --json <name>` run, made
/// lazily when the card was opened — never on a poll tick. Identity and status
/// stay on the card's face; this renders only what the probe added.
struct ServiceCardDetail: View {
    let services: ServicesStore
    /// The seam. `BrewClient` owns the protocol; this target owns the single
    /// `NSWorkspace` implementation.
    let opener: any LogFileOpening

    var body: some View {
        // Which of the outcomes this is — reading, answered, failed — is
        // decided by `ServiceDetailLoadState.pane` in `BrewClient`, inside the
        // `swift test` inner loop. Branching here on `detail != nil` alone is
        // what reported a **failed** probe as nothing-selected, with brew's
        // reason discarded.
        switch services.detailState.pane {
        case .detail(let detail):
            content(for: detail)
        case .notice(let notice):
            noticeView(notice)
        }
    }

    @ViewBuilder
    private func content(for detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Details")
            if let pid = detail.pid {
                fact("Process", String(pid))
            }
            if let plist = detail.plistPath {
                fact("Property list", plist.path)
            }
            logs(for: detail)
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
        VStack(alignment: .leading, spacing: 8) {
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

    /// A probe still in flight and a probe that failed are different facts,
    /// and rendering either as silence tells the user the card has nothing —
    /// when in truth brew was asked and has not, or could not, answer. The
    /// words live in `ServicesPresentation`; this owns only the layout.
    @ViewBuilder
    private func noticeView(_ notice: ServiceDetailNotice) -> some View {
        switch notice {
        case .nothingSelected:
            // Unreachable while a card is expanded — the expansion is the
            // selection — but rendered honestly rather than swallowed.
            EmptyView()
        case .reading, .failed:
            Text(notice.message)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
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
    ServiceCardDetail(services: ServicesStore(), opener: NoLogFileOpening())
        .padding(20)
        .background(Theme.windowBackground)
}
