//
//  ActivityDrawer.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The expanded activity list: every operation this session, with its state, the
/// exact command, a copy affordance and its streamed log.
///
/// Terminal items stay listed for the rest of the session
/// (operation-activity OA1); persistence across launches is M2-3.
struct ActivityDrawer: View {
    let center: OperationCenter

    @State private var expandedID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(center.items) { item in
                    ActivityRow(
                        item: item,
                        isExpanded: expandedID == item.id,
                        onToggle: { expandedID = expandedID == item.id ? nil : item.id },
                        onCancel: { center.cancel(item) }
                    )
                    Divider()
                }
            }
        }
        .frame(height: 220)
    }
}

/// One operation in the drawer.
private struct ActivityRow: View {
    let item: ActivityItem
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide log" : "Show log")

                Text(item.displayCommand)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Text(item.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Copy is offered in every state and produces the same text in
                // each — it is the same pure projection of the same command.
                CopyCommandButton(text: item.copyText)

                // Cancel is offered from pending and running, and nowhere else.
                // There is deliberately no reorder and no remove.
                if item.isCancellable {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.borderless)
                }
            }

            Text(item.message)
                .font(.caption)
                .foregroundStyle(item.outcome?.isFailure == true ? .primary : .secondary)
                .textSelection(.enabled)

            if isExpanded {
                ActivityLogView(item: item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Copies the exact command that ran, with no decoration beyond making it
/// pasteable.
struct CopyCommandButton: View {
    let text: String

    @State private var hasCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            hasCopied = true
        } label: {
            Label(
                hasCopied ? "Copied" : "Copy command",
                systemImage: hasCopied ? "checkmark" : "doc.on.doc"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Copy \(text)")
        .accessibilityLabel("Copy command")
    }
}
