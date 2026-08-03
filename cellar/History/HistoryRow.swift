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
                Text(outcomeLabel).font(.caption)
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

    /// A grouped `upgradeAll` names no package, and the row says so rather than
    /// rendering an empty gap.
    private var title: String {
        record.name.isEmpty ? "All packages" : record.name
    }

    /// The stored outcome, spelled for a human. Read off `outcomeRaw`, which the
    /// classifier decided — never off anything brew printed.
    private var outcomeLabel: String {
        switch record.outcomeRaw {
        case "succeeded": "Done"
        case "noChange": "No change"
        case "failed": record.exitStatus.map { "Failed (\($0))" } ?? "Failed"
        case "busy": "Homebrew busy"
        case "needsPrivileges": "Needs Terminal"
        case "cancelled": "Cancelled"
        case "abandoned": "Cancelled, still running"
        case "launchFailed": "Could not start"
        default: record.outcomeRaw
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
