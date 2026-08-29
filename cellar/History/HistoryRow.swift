//
//  HistoryRow.swift
//  cellar
//

import Persistence
import SwiftUI

/// One durable entry, as a row.
///
/// It owns no rule at all: the name, the verb, the transition, the outcome
/// label and the copy text are all read straight off `HistoryRecord`, which is
/// a plain value proven in the package's own suite. There is deliberately **no
/// per-entry delete control** — clearing is all-or-nothing behind a
/// confirmation, and `HistoryRecord.controls` says so assertably rather than by
/// this view happening not to draw one (installation-history IH6 sc4).
struct HistoryRow: View {
    let record: HistoryRecord

    /// Collapsed by default: the tail is an explanation on demand, not a
    /// second row competing with the list.
    @State private var showsFailureTail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showsFailureTail {
                failureTail
            }
        }
        .padding(.vertical, 5)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: verbSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(verbColor)
                .frame(width: 26, height: 26)
                .background(verbFill, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.mono(12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(record.sourceLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1.5)
                        .background(
                            Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .accessibilityIdentifier("history-source-badge")
                    Text(record.verb)
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1.5)
                        .background(
                            Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                // The exact argv that ran, verbatim, behind the executable that
                // ran it — the same projection the copy button produces, and
                // display only either way. The prefix is derived from the row's
                // own stored kind, so an npm row reads as an npm command and can
                // never read as a brew one (`installation-history`).
                Text(record.displayCommand)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .textSelection(.enabled)
                if let versions = record.versions {
                    Text("\(versions.from) → \(versions.to)")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.outcomeLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(outcomeColor)
                Text(record.date, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.34))
                // Only rows that stored a tail offer one — entries written
                // before the field existed have nothing to disclose.
                if !record.failureTail.isEmpty {
                    Button(showsFailureTail ? "Hide error" : "Show error") {
                        showsFailureTail.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dangerText)
                    .accessibilityIdentifier("history-failure-disclosure")
                }
            }
            if record.controls.contains(.copyCommand) {
                Button {
                    copy(record.displayCommand)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .buttonStyle(.borderless)
                .help("Copy \(record.displayCommand)")
            }
        }
    }

    /// The failure's own words, verbatim and display-only — the same newest
    /// lines the Activity log showed while the run was alive.
    private var failureTail: some View {
        Text(record.failureTail.joined(separator: "\n"))
            .font(Theme.mono(11))
            .foregroundStyle(Color.white.opacity(0.65))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.dangerTint(0.07),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .accessibilityIdentifier("history-failure-tail")
    }

    private var verbSymbol: String {
        switch record.verb {
        case "install": "arrow.down"
        case "uninstall", "zap": "trash"
        case "start", "stop", "restart": "gearshape"
        default: "arrow.up"
        }
    }

    private var verbColor: Color {
        switch record.verb {
        case "install": Theme.successText
        case "uninstall", "zap": Theme.dangerText
        case "start", "stop", "restart": Color.white.opacity(0.55)
        default: Theme.infoText
        }
    }

    private var verbFill: Color {
        switch record.verb {
        case "install": Theme.successTint(0.16)
        case "uninstall", "zap": Theme.dangerTint(0.16)
        case "start", "stop", "restart": Color.white.opacity(0.06)
        default: Color(.sRGB, red: 127 / 255, green: 178 / 255, blue: 232 / 255, opacity: 0.16)
        }
    }

    private var outcomeColor: Color {
        switch record.outcomeRaw {
        case "succeeded": Theme.successText
        case "failed": Theme.dangerText
        default: Color.white.opacity(0.5)
        }
    }

    /// What the entry acted on, read off `HistoryRecord.subject`.
    ///
    /// The rule is **not** "empty name means all packages": storage spells a
    /// grouped `upgradeAll` and a service verb's null package identity the same
    /// way, and only the verb separates them. Deciding here on the empty string
    /// would title `brew services stop atuin` as "All packages" — the borrowed
    /// identity IH1 forbids. The projection is proven in `swift test`
    /// (`HistorySubjectTests`); this view owns no rule.
    private var title: String {
        record.subject.label
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
