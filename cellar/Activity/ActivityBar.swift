//
//  ActivityBar.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The always-visible activity strip.
///
/// An inset rather than a sheet, and hidden **entirely** when nothing is queued:
/// a mutation is background work, and a sheet would hold the app hostage while
/// brew compiles for ten minutes (design D10).
///
/// It owns no rules. Whether there is work, what is running, how many are
/// queued and whether cancel is offered are all computed properties on
/// `OperationCenter` / `ActivityItem`, proven in the package's own test suite.
struct ActivityBar: View {
    let center: OperationCenter
    @Binding var isExpanded: Bool

    var body: some View {
        if center.items.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Divider()
                if isExpanded {
                    ActivityDrawer(center: center)
                    Divider()
                }
                collapsedBar
            }
            .background(.bar)
        }
    }

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = subheadline {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let running = center.summary.running {
                Button("Cancel") { center.cancel(running) }
                    .buttonStyle(.borderless)
                    .help("Stop \(running.displayCommand)")
            }
            Button {
                isExpanded.toggle()
            } label: {
                Label(
                    isExpanded ? "Hide activity" : "Show activity",
                    systemImage: isExpanded ? "chevron.down" : "chevron.up"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if center.summary.isBusy {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        center.summary.runningCommand ?? "No package changes running"
    }

    private var subheadline: String? {
        let pending = center.summary.pendingCount
        guard pending > 0 else { return nil }
        return pending == 1 ? "1 queued" : "\(pending) queued"
    }
}

#Preview("Idle — the bar is absent") {
    ActivityBar(center: OperationCenter(), isExpanded: .constant(false))
        .frame(width: 640)
}
