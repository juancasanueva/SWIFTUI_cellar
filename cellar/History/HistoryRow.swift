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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.medium))
                    Text(record.verb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // The exact argv that ran, verbatim — the same projection the
                // copy button produces, and display only either way.
                Text(record.commandText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let versions = record.versions {
                    Text("\(versions.from) → \(versions.to)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.outcomeLabel).font(.caption)
                Text(record.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if record.controls.contains(.copyCommand) {
                Button {
                    copy(record.commandText)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(record.commandText)")
            }
        }
        .padding(.vertical, 2)
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
