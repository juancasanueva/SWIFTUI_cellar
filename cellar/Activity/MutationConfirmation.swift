//
//  MutationConfirmation.swift
//  cellar
//

import BrewClient
import Catalog
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
    let currentForceEvidence: @MainActor @Sendable (TapName) -> ForceUntapEvidence?
    let confirmCleanup: @MainActor @Sendable (OperationCenter.ConfirmationRequest) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: pending) { request in
            MutationConfirmationSheet(
                request: request,
                center: center,
                currentForceEvidence: currentForceEvidence,
                confirmCleanup: confirmCleanup
            )
        }
    }

    private var pending: Binding<OperationCenter.ConfirmationRequest?> {
        Binding(
            get: { center.pendingConfirmation },
            // Dismissing without choosing is a decline: nothing is submitted and
            // nothing is spawned.
            set: { presented in
                guard presented == nil, let request = center.pendingConfirmation else { return }
                center.decline(request)
            }
        )
    }
}

private struct MutationConfirmationSheet: View {
    let request: OperationCenter.ConfirmationRequest
    let center: OperationCenter
    let currentForceEvidence: @MainActor @Sendable (TapName) -> ForceUntapEvidence?
    let confirmCleanup: @MainActor @Sendable (OperationCenter.ConfirmationRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(request.isBulk ? "This will run \(request.commands.count) commands:" : "This will run:")
                    ForEach(Array(request.displayCommands.enumerated()), id: \.offset) { _, command in
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier(
                                request.cleanupDisclosure == nil ? "confirmation-command" : "cleanup-command"
                            )
                    }
                    Text(request.warningText)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("confirmation-warning")

                    if !request.affectedPackages.isEmpty {
                        Text("Affected packages")
                            .font(.headline)
                        ForEach(request.affectedPackages, id: \.self) { package in
                            Text("\(package.kind.rawValue): \(package.name)")
                                .accessibilityIdentifier(
                                    "confirmation-affected-\(package.kind.rawValue)-\(package.name)"
                                )
                        }
                    }

                    if let cleanup = request.cleanupDisclosure {
                        cleanupDisclosure(cleanup)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                if request.cleanupDisclosure != nil {
                    Button(role: .cancel) {
                        center.decline(request)
                    } label: {
                        Text("Cancel").accessibilityIdentifier("cleanup-cancel")
                    }
                    .accessibilityIdentifier("cleanup-cancel")
                } else {
                    Button("Cancel", role: .cancel) {
                        center.decline(request)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(confirmLabel, role: .destructive) {
                    confirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 300, idealHeight: 380)
        .accessibilityIdentifier(
            request.cleanupDisclosure == nil ? "mutation-confirmation" : "cleanup-confirmation"
        )
    }

    @ViewBuilder
    private func cleanupDisclosure(_ disclosure: CleanupConfirmationDisclosure) -> some View {
        Text("Scope and effects")
            .font(.headline)
        Text(cleanupEffects(disclosure))
        Text(provenance(disclosure))
            .textSelection(.enabled)
            .accessibilityIdentifier("cleanup-provenance")

        if let count = disclosure.orphanCount {
            Text("\(count) \(count == 1 ? "orphan" : "orphans") reported by Homebrew")
                .accessibilityIdentifier("cleanup-orphan-count")
        }
        ForEach(disclosure.orphanNames, id: \.self) { name in
            Text(name).accessibilityIdentifier("cleanup-orphan-\(name)")
        }
        if let bytes = disclosure.evidence.orphans.currentlyOnDiskBytes {
            Text("\(bytes.formatted(.byteCount(style: .file))) currently on disk")
                .accessibilityIdentifier("cleanup-orphan-allocation")
        }
        if let warning = disclosure.fullWarning {
            Text(warning)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cleanup-full-warning")
        }
    }

    private var title: String {
        if let cleanup = request.cleanupDisclosure {
            return "Confirm \(scopeName(cleanup.scope))?"
        }
        switch request.disclosure {
        case .tapTrust: return "Add this tap?"
        case .forceUntap: return "Force-remove this tap?"
        case .packageRemoval: break
        }
        if request.isBulk {
            return "Uninstall \(request.commands.count) packages?"
        }
        return request.isZap
            ? "Remove this cask and everything it left behind?"
            : "Uninstall this package?"
    }

    private var confirmLabel: String {
        if request.cleanupDisclosure != nil { return "Confirm Cleanup" }
        switch request.disclosure {
        case .tapTrust: return "Add Tap"
        case .forceUntap: return "Force Untap"
        case .packageRemoval: break
        }
        if request.isBulk { return "Uninstall \(request.commands.count)" }
        return request.isZap ? "Uninstall and Zap" : "Uninstall"
    }

    private func confirm() {
        if request.cleanupDisclosure != nil {
            confirmCleanup(request)
            return
        }
        guard case .forceUntap(let tap, _) = request.disclosure else {
            center.confirm(request)
            return
        }
        Task {
            await center.confirmForceUntap(request) {
                currentForceEvidence(tap)
            }
        }
    }

    private func scopeName(_ scope: CleanupScope) -> String {
        switch scope {
        case .global: "Cleanup"
        case .full: "Full cleanup"
        case .autoremove: "Autoremove"
        case .package(let target): "cleanup for \(target.name)"
        }
    }

    private func cleanupEffects(_ disclosure: CleanupConfirmationDisclosure) -> String {
        switch disclosure.scope {
        case .global, .package:
            "Removes only the cleanup candidates in this preview. Autoremove is disabled."
        case .full:
            "Removes the listed cleanup candidates and cached downloads regardless of age. Autoremove is disabled."
        case .autoremove:
            "Removes the exact formulae listed as no longer required dependencies."
        }
    }

    private func provenance(_ disclosure: CleanupConfirmationDisclosure) -> String {
        switch disclosure.total {
        case .reportedFooter(let bytes):
            "Homebrew reported \(bytes.formatted(.byteCount(style: .file))) reclaimable in its preview footer. Parser v\(disclosure.provenance.parserVersion)."
        case .unknown:
            "Homebrew did not report a reclaimable total. Row sizes are not substituted. Parser v\(disclosure.provenance.parserVersion)."
        }
    }
}

private extension OperationCenter.ConfirmationRequest {
    /// Whether this is the zap confirmation rather than the ordinary uninstall.
    ///
    /// Read from the request's **verb** rather than by switching on a command
    /// case: the request carries an erased `AnyBrewMutation` now, so any family
    /// may reach this sheet and only this capability's `zap` should retitle it.
    /// `MutationCommand.verb` is the same projection the durable history is
    /// searched by, and it already distinguishes zap from an ordinary uninstall
    /// for exactly this reason.
    var isZap: Bool { command.verb == "zap" }
}

extension View {
    /// Presents the centre's pending confirmation, if there is one.
    func mutationConfirmation(
        _ center: OperationCenter,
        currentForceEvidence: @escaping @MainActor @Sendable (TapName) -> ForceUntapEvidence? = { _ in nil },
        confirmCleanup: @escaping @MainActor @Sendable (OperationCenter.ConfirmationRequest) -> Void = { _ in }
    ) -> some View {
        modifier(
            MutationConfirmation(
                center: center,
                currentForceEvidence: currentForceEvidence,
                confirmCleanup: confirmCleanup
            )
        )
    }
}
