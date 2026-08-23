//
//  ActivityDrawer.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The expanded activity list: every operation this session, with its state, the
/// exact command, a copy affordance and its streamed log.
///
/// Terminal items stay listed for the rest of the session
/// (operation-activity OA1); persistence across launches is M2-3.
struct ActivityDrawer: View {
    let center: OperationCenter
    /// Which tap Cellar may offer to trust after an untrusted-tap refusal, for
    /// a given refused package identity.
    ///
    /// A closure rather than a `TapStore`, in the shipped `currentForceEvidence`
    /// idiom: the drawer stays ignorant of tap storage, and this is the only
    /// thing that can turn a refused `PackageID` into a typed command
    /// (design DD-12).
    let trustableTap: @MainActor (PackageID?) -> TapName?

    @State private var expandedID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(center.items) { item in
                    ActivityRow(
                        item: item,
                        isExpanded: expandedID == item.id,
                        // The refusal carries no tap — nothing is parsed out of
                        // it — so the candidate comes from Cellar's own
                        // snapshot, keyed by an identity Cellar typed itself.
                        recoverableTap: item.outcome == .refusedUntrustedTap
                            ? trustableTap(item.command.packageID)
                            : nil,
                        onToggle: { expandedID = expandedID == item.id ? nil : item.id },
                        onCancel: { center.cancel(item) },
                        onTrust: { tap in _ = center.request(TapCommand.trustTap(tap)) }
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
    /// Non-`nil` only for a refusal with exactly one untrusted publisher. With
    /// zero or two, the typed message's own sentence is the path and no button
    /// is shown, because Cellar will not guess which capability to grant
    /// (design DD-7, R16).
    let recoverableTap: TapName?
    let onToggle: () -> Void
    let onCancel: () -> Void
    let onTrust: (TapName) -> Void

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

                // Opens the ordinary **confirmed** Trust request. It retries
                // nothing: a requalified retry is precisely what would turn a
                // refusal into silent execution of unconsented code.
                if let recoverableTap {
                    Button("Trust") { onTrust(recoverableTap) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("activity-trust-recovery")
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
