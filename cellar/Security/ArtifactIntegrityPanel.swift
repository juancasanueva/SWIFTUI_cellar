//
//  ArtifactIntegrityPanel.swift
//  cellar
//

import BrewClient
import Catalog
import Observation
import SecurityKit
import SwiftUI

/// Holds the sweep's results as they stream in.
///
/// Deliberately small and app-side: the reports are not cached, so there is no
/// ordinal, no last-good and no adoption guard to reproduce. A signature
/// assessment costs tens of milliseconds of local work and describes the artifact
/// **as it is now** — persisting it would mean showing a verdict about bytes that
/// may have changed since.
@MainActor
@Observable
final class ArtifactIntegrityStore {
    private(set) var reports: [ArtifactIntegrityReport] = []
    private(set) var isRunning = false
    /// Whether the last run reached the end. A cancelled sweep leaves this
    /// `false`, so the panel can say "partial" rather than presenting an
    /// interrupted list as the whole picture.
    private(set) var isComplete = false
    private(set) var expected = 0

    @ObservationIgnored private let engine: ArtifactIntegrityEngine
    @ObservationIgnored private var task: Task<Void, Never>?

    init(engine: ArtifactIntegrityEngine = ArtifactIntegrityEngine()) {
        self.engine = engine
    }

    func run(over locations: [ArtifactLocation]) {
        task?.cancel()
        reports = []
        isComplete = false
        isRunning = true

        task = Task { [engine] in
            defer { isRunning = false }
            // Results are adopted one at a time, exactly as they arrive: a
            // terminal batch would be a multi-second freeze with nothing on
            // screen over a real inventory. A cancelled sweep simply stops —
            // `isComplete` stays false, and the reports already in hand remain.
            let stream = await engine.inspect(locations)
            do {
                for try await event in stream {
                    switch event {
                    case .started(let count): expected = count
                    case .assessed(let report): reports.append(report)
                    case .finished: isComplete = true
                    }
                }
            } catch {
                // Cancellation is the only way out of this stream, and it is not
                // a failure of any artifact.
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }
}

/// Signing, notarization and quarantine, shown together.
///
/// **There is no clearing, removing, re-signing or stapling affordance anywhere
/// in this file.** Task 14.11 asserts the same prohibition over the capability's
/// public surface; this is the UI half of one rule, and the two are asserted
/// separately because a surface with no method and a method with no button are
/// different failures.
struct ArtifactIntegrityPanel: View {
    let store: ArtifactIntegrityStore
    let locations: [ArtifactLocation]

    var body: some View {
        List {
            summary
            ForEach(store.reports) { report in
                row(report)
            }
        }
        .navigationTitle("Artifact integrity")
        .toolbar {
            if store.isRunning {
                Button("Cancel") { store.cancel() }
                    .accessibilityIdentifier("security-integrity-cancel")
            } else {
                Button("Check artifacts") { store.run(over: locations) }
                    .accessibilityIdentifier("security-integrity-run")
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                let totals = NotarizationTotals(of: store.reports.map(\.signature.notarization))
                Text("\(store.reports.count) of \(store.expected) artifacts checked")
                    .font(.headline)
                // Three counts, kept three. Folding "could not assess" into
                // "not notarized" would silently decide every artifact whose
                // ticket this build cannot resolve.
                Text(
                    """
                    \(totals.notarized) notarized, \(totals.notNotarized) not notarized, \
                    \(totals.couldNotAssess) could not be assessed.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if store.isRunning || (store.isComplete == false && store.reports.isEmpty == false) {
                    Text(store.isRunning ? "Checking…" : "Stopped before the end — this is a partial list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("security-integrity-summary")
        }
    }

    @ViewBuilder
    private func row(_ report: ArtifactIntegrityReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(report.location.packageID.name)
                    .font(.callout.weight(.medium))
                Text(report.location.url.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(report.signature.notarization.label)
                    .font(.caption)
            }
            Text(report.signature.signing.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            // `couldNotAssess` renders as itself, with its reason — never as a
            // blank, and never as one of the two verdicts it is not.
            if let reason = report.signature.notarization.reason {
                Text(reason.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let quarantine = report.quarantine?.quarantine {
                quarantineDetail(quarantine)
            }
            if report.quarantine?.hasProvenance == true {
                Text("Carries a provenance attribute. Its contents are undocumented and not read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("security-integrity-\(report.location.packageID.name)")
    }

    /// The decoded components **and** the raw value, together.
    @ViewBuilder
    private func quarantineDetail(_ attribute: QuarantineAttribute) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Quarantined")
                .font(.caption.weight(.semibold))
            LabeledContent("Flags", value: attribute.flagsDescription)
            LabeledContent("Recorded", value: Self.describe(attribute.timestamp))
            LabeledContent("By", value: Self.describeAgent(attribute.agentName))
            Text(attribute.rawValue)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("security-integrity-raw-attribute")
        }
        .font(.caption)
    }

    private static func describe(_ component: QuarantineComponent<Date>) -> String {
        switch component {
        case .decoded(let date): date.formatted(date: .abbreviated, time: .shortened)
        case .absent: "Not recorded"
        case .unknown(let raw): "Unrecognised (\(raw))"
        }
    }

    /// An empty agent is "not recorded", not "unknown". The U3 probe found the
    /// field empty on two of three quarantined apps, and calling an ordinary
    /// attribute unrecognised would report a normal file as damaged.
    private static func describeAgent(_ component: QuarantineComponent<String>) -> String {
        switch component {
        case .decoded(let agent): agent
        case .absent: "Not recorded"
        case .unknown(let raw): "Unrecognised (\(raw))"
        }
    }
}
