//
//  ActivityBar.swift
//  cellar
//

import BrewClient
import Catalog
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
    /// Forwarded to the drawer unchanged; the bar owns no rule about it.
    let trustableTap: @MainActor (PackageID?) -> TapName?

    var body: some View {
        if center.items.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.5)
                if isExpanded {
                    ActivityDrawer(center: center, trustableTap: trustableTap)
                        .background(Theme.logWell)
                    HairlineDivider()
                }
                collapsedBar
            }
            .background(Color.white.opacity(0.03))
            .background(Theme.windowBackground)
        }
    }

    private var collapsedBar: some View {
        HStack(spacing: 12) {
            statusIcon
            Text(headline)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = subheadline {
                Text(detail)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Color.white.opacity(0.44))
            }
            Spacer(minLength: 8)
            if let running = center.summary.running {
                Button("Cancel") { center.cancel(running) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(
                        Theme.controlFillLoud,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .help("Stop \(running.displayCommand)")
            }
            Button {
                isExpanded.toggle()
            } label: {
                Text(isExpanded ? "Hide log" : "Show log")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            // The design writes "log"; the affordance keeps its shipped
            // accessible name, which the UI tests click by.
            .accessibilityLabel(isExpanded ? "Hide activity" : "Show activity")
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if center.summary.isBusy {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.successBase)
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
    ActivityBar(center: OperationCenter(), isExpanded: .constant(false), trustableTap: { _ in nil })
        .frame(width: 640)
}
