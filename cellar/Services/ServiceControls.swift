//
//  ServiceControls.swift
//  cellar
//

import AppKit
import BrewClient
import SwiftUI

/// The four service verbs, plus copy-command, as separately labelled and
/// separately invoked controls (design D8 — service-management SM5).
///
/// **Start-at-login and run-once are two controls, never one with a flag.**
/// `brew services start` registers the service to launch at login;
/// `brew services run` does not. That is a change to the user's login items, so
/// no default, implicit or hidden choice may decide it on their behalf, and each
/// label states in words which of the two it does (ruling #7182-3).
///
/// The view owns no rule at all. Which controls exist is
/// `ServiceRowControl.allCases`, what each one submits is
/// `ServiceRowControl.command(for:)`, and whether a second submission is refused
/// is the centre's guard — all proven in the `swift test` inner loop, so what is
/// untested by design here is layout only.
struct ServiceControls: View {
    let service: ServiceRecord
    let operations: OperationCenter

    /// `nil` only for a name brew could read as an option, in which case every
    /// control is simply absent — an unvalidated command is not representable,
    /// so there is nothing to disable (SM4, PM9).
    private var target: ServiceTarget? { ServiceTarget(service) }

    var body: some View {
        if let target {
            HStack(spacing: 8) {
                ForEach(ServiceRowControl.allCases, id: \.self) { control in
                    button(control, target)
                }
            }
            .disabled(!operations.isAvailable)
            .help(operations.unavailableGuidance ?? "Start, stop or restart \(service.name)")
        }
    }

    @ViewBuilder
    private func button(_ control: ServiceRowControl, _ target: ServiceTarget) -> some View {
        Button(control.label) { invoke(control, target) }
            .buttonStyle(ActionPillStyle())
            .accessibilityLabel("\(control.label) \(service.name)")
    }

    /// One entry point for every control, so the submission rule is applied in
    /// exactly one place rather than restated per button.
    ///
    /// Through `submit(service:)` rather than the general `submit`, which is
    /// what makes a double-click return the operation already running instead of
    /// queueing a contradictory one (SM10).
    private func invoke(_ control: ServiceRowControl, _ target: ServiceTarget) {
        guard let command = control.command(for: target) else {
            copy(ServiceCommand.start(target).displayCommand)
            return
        }
        operations.submit(service: command)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    List {
        ServiceControls(
            service: ServiceRecord(name: "atuin", status: .none),
            operations: OperationCenter()
        )
    }
}
