//
//  ServiceRow.swift
//  cellar
//

import BrewClient
import SwiftUI

/// One background service as a card: identity and the five verbs on the face,
/// the probe-backed detail behind a click on the identity.
///
/// The disclosure is hand-built — the `CleanupRow` and
/// `ArtifactIntegritySection` precedent — so the verbs stay their own,
/// clickable controls beside a toggle that spans the rest of the card.
struct ServiceCard: View {
    let service: ServiceRecord
    let services: ServicesStore
    let operations: OperationCenter
    let opener: any LogFileOpening
    /// The one expanded card. Shared state rather than per-card, because the
    /// detail probe answers for one service at a time (SM: probe on selection
    /// only), so two open cards would show one service's answers twice.
    @Binding var selection: String?

    private var isExpanded: Bool { selection == service.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    selection = isExpanded ? nil : service.id
                } label: {
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
                        if let user = service.user {
                            Text(user)
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Color.white.opacity(0.38))
                                .help("Runs as \(user)")
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("service-card-\(service.name)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Hides the service's details" : "Shows the service's details")
                ServiceControls(service: service, operations: operations)
            }
            if isExpanded {
                ServiceCardDetail(services: services, opener: opener)
                    .padding(EdgeInsets(top: 14, leading: 41, bottom: 2, trailing: 0))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .themeCard(radius: 10)
        .accessibilityElement(children: .contain)
    }

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
    @Previewable @State var selection: String?
    let services = ServicesStore()
    let operations = OperationCenter()
    return ScrollView {
        VStack(spacing: 12) {
            ServiceCard(
                service: ServiceRecord(name: "atuin", status: .started, user: "tester"),
                services: services,
                operations: operations,
                opener: NoLogFileOpening(),
                selection: $selection
            )
            ServiceCard(
                service: ServiceRecord(name: "postgresql@16", status: .none),
                services: services,
                operations: operations,
                opener: NoLogFileOpening(),
                selection: $selection
            )
            ServiceCard(
                service: ServiceRecord(name: "unbound", status: .error, exitCode: 1),
                services: services,
                operations: operations,
                opener: NoLogFileOpening(),
                selection: $selection
            )
        }
        .padding(20)
    }
    .background(Theme.windowBackground)
}
