//
//  ServiceRow.swift
//  cellar
//

import BrewClient
import SwiftUI

/// One background service: its name and what brew says it is doing.
///
/// **No controls yet.** The four verbs are separately labelled, separately
/// invoked actions and they arrive with the mutation spine; a row that showed
/// them before they could be submitted would be an affordance that does
/// nothing, which is exactly the failure mode this project refuses elsewhere.
struct ServiceRow: View {
    let service: ServiceRecord

    var body: some View {
        HStack(spacing: 8) {
            Text(service.name)
                .font(.body)
                .lineLimit(1)
            ServiceStatusTag(status: service.status)
            Spacer(minLength: 0)
            if let user = service.user {
                Text(user)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Runs as \(user)")
            }
        }
        .padding(.vertical, 2)
    }
}

/// The status, coloured by its tone.
///
/// The label and the tone are `BrewClient`'s pure projection; the only thing
/// decided here is which colour draws each tone, because `Color` is SwiftUI's
/// and the core is GUI-free.
struct ServiceStatusTag: View {
    let status: ServiceStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(status.label)")
    }

    private var color: Color {
        switch status.tone {
        case .running: .green
        case .idle: .secondary
        case .scheduled: .blue
        case .failed: .red
        // Not red: brew reported something this build cannot interpret, and
        // colouring it as a failure would present a guess as brew's report.
        case .indeterminate: .orange
        }
    }
}

#Preview {
    List {
        ServiceRow(service: ServiceRecord(name: "atuin", status: .started, user: "tester"))
        ServiceRow(service: ServiceRecord(name: "postgresql@16", status: .none))
        ServiceRow(service: ServiceRecord(name: "unbound", status: .error, exitCode: 1))
        ServiceRow(service: ServiceRecord(name: "enigma", status: .unrecognised("mystery")))
    }
}
