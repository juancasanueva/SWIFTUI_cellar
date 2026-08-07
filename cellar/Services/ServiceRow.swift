//
//  ServiceRow.swift
//  cellar
//

import BrewClient
import SwiftUI

/// One background service: its name, what brew says it is doing, and the five
/// controls it offers.
///
/// The controls arrive with the mutation spine rather than before it: a row that
/// showed them while nothing could be submitted would be an affordance that does
/// nothing, which is the failure mode this project refuses elsewhere.
struct ServiceRow: View {
    let service: ServiceRecord
    let operations: OperationCenter

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(dotWell)
                Circle().fill(dot).frame(width: 9, height: 9)
            }
            .frame(width: 30, height: 30)
            Text(service.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            ServiceStatusTag(status: service.status)
            Spacer(minLength: 0)
            if let user = service.user {
                Text(user)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .help("Runs as \(user)")
            }
            ServiceControls(service: service, operations: operations)
        }
        .padding(.vertical, 4)
    }

    private var isRunning: Bool { service.status.tone == .running }

    private var dot: Color {
        switch service.status.tone {
        case .running: Theme.successBase
        case .idle: Color.white.opacity(0.3)
        case .scheduled: Theme.infoText
        case .failed: Theme.dangerBase
        case .indeterminate: .orange
        }
    }

    private var dotWell: Color {
        switch service.status.tone {
        case .running: Theme.successTint(0.14)
        case .failed: Theme.dangerTint(0.14)
        default: Color.white.opacity(0.05)
        }
    }
}

/// The status, as the design's uppercase chip.
///
/// The label and the tone are `BrewClient`'s pure projection; the only thing
/// decided here is which colour draws each tone, because `Color` is SwiftUI's
/// and the core is GUI-free.
struct ServiceStatusTag: View {
    let status: ServiceStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .bold))
            .kerning(0.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel("Status: \(status.label)")
    }

    private var color: Color {
        switch status.tone {
        case .running: Theme.successText
        case .idle: Color.white.opacity(0.45)
        case .scheduled: Theme.infoText
        case .failed: Theme.dangerText
        // Not red: brew reported something this build cannot interpret, and
        // colouring it as a failure would present a guess as brew's report.
        case .indeterminate: .orange
        }
    }

    private var fill: Color {
        switch status.tone {
        case .running: Theme.successTint(0.16)
        case .failed: Theme.dangerTint(0.16)
        default: Theme.controlFill
        }
    }
}

#Preview {
    let operations = OperationCenter()
    return List {
        ServiceRow(
            service: ServiceRecord(name: "atuin", status: .started, user: "tester"),
            operations: operations
        )
        ServiceRow(service: ServiceRecord(name: "postgresql@16", status: .none), operations: operations)
        ServiceRow(service: ServiceRecord(name: "unbound", status: .error, exitCode: 1), operations: operations)
        ServiceRow(
            service: ServiceRecord(name: "enigma", status: .unrecognised("mystery")),
            operations: operations
        )
    }
}
