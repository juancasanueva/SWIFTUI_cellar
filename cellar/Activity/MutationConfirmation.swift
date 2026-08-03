//
//  MutationConfirmation.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The confirmation for the two destructive commands.
///
/// It renders `displayCommand` **verbatim** — the same string the copy
/// affordance produces, and character for character the argv that will run. The
/// string is display only: confirming submits the typed command the request
/// carries, so nothing here can change what runs (design D6, D2).
///
/// Zap is a separate choice, offered separately and confirmed separately. It is
/// never implied by an ordinary uninstall (package-mutation PM3).
struct MutationConfirmation: ViewModifier {
    let center: OperationCenter

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: isPresented,
            titleVisibility: .visible,
            presenting: center.pendingConfirmation
        ) { request in
            Button(confirmLabel(for: request), role: .destructive) {
                center.confirm(request)
            }
            Button("Cancel", role: .cancel) {
                center.decline(request)
            }
        } message: { request in
            // Every command, verbatim, one per line. A bulk uninstall discloses
            // all of them — not a count and not an elided subset, because an
            // all-or-nothing destructive action must never be confirmed blind
            // (package-mutation PM3 sc5).
            Text(request.isBulk ? bulkMessage(request) : "This will run:\n\(request.displayCommand)")
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { center.pendingConfirmation != nil },
            // Dismissing without choosing is a decline: nothing is submitted and
            // nothing is spawned.
            set: { presented in
                guard !presented, let request = center.pendingConfirmation else { return }
                center.decline(request)
            }
        )
    }

    private func bulkMessage(_ request: OperationCenter.ConfirmationRequest) -> String {
        "This will run \(request.commands.count) commands:\n"
            + request.displayCommands.joined(separator: "\n")
    }

    private var title: String {
        guard let request = center.pendingConfirmation else { return "" }
        if request.isBulk {
            return "Uninstall \(request.commands.count) packages?"
        }
        return switch request.command {
        case .zap: "Remove this cask and everything it left behind?"
        default: "Uninstall this package?"
        }
    }

    private func confirmLabel(for request: OperationCenter.ConfirmationRequest) -> String {
        if request.isBulk { return "Uninstall \(request.commands.count)" }
        return switch request.command {
        case .zap: "Uninstall and Zap"
        default: "Uninstall"
        }
    }
}

extension View {
    /// Presents the centre's pending confirmation, if there is one.
    func mutationConfirmation(_ center: OperationCenter) -> some View {
        modifier(MutationConfirmation(center: center))
    }
}
