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

    init(
        engine: ArtifactIntegrityEngine = ArtifactIntegrityEngine(),
        initialReports: [ArtifactIntegrityReport] = []
    ) {
        self.engine = engine
        // The `DiskUsageStore(initialSnapshot:)` precedent: a UI test needs a
        // deterministic surface, and a real sweep depends on what happens to be
        // installed. Empty in every ordinary launch.
        reports = initialReports
        expected = initialReports.count
        isComplete = initialReports.isEmpty == false
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

    /// Which rows have their signing identity open, keyed by artifact URL.
    ///
    /// Held here rather than left to `DisclosureGroup`'s implicit state, because
    /// the implicit version is what shipped broken: nested inside a row's
    /// `VStack` with a bare `String` label it rendered **no indicator at all**
    /// and had no usable click target. See `signingIdentity`.
    @State private var expandedIdentities: Set<URL> = []

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
            // The row anchor sits on the header line rather than on the whole
            // row. An identifier on the outer container **overrides every
            // descendant's** — measured: the identity button reported
            // `security-integrity-ghostty`, and every field inside the
            // disclosure would have collapsed onto the same string, leaving the
            // authority chain unaddressable from a UI test.
            .accessibilityIdentifier("security-integrity-\(report.location.packageID.name)")
            HStack(spacing: 6) {
                Text(report.signature.signing.label)
                // The identifier inline as well as in the disclosure below. It is
                // the single most identifying value, it is short, and "signed by
                // <team>" on its own is what shipped and was rightly called out:
                // a team identifier is not an identity.
                if let identifier = report.signature.signing.identity?.identifier {
                    Text(identifier)
                        .monospaced()
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier(
                            "security-integrity-\(report.location.packageID.name)-identifier-inline"
                        )
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            signingIdentity(report)
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
    }

    /// Identifier, team and the full authority chain, behind one disclosure.
    ///
    /// **Why a hand-built disclosure rather than `DisclosureGroup`.** The first
    /// version used `DisclosureGroup("Signing identity")` nested inside the row's
    /// `VStack`, and it shipped **non-interactive**: no indicator rendered and
    /// clicking did nothing, so the authority chain was unreachable and MV-7
    /// could not close. The app's one working `DisclosureGroup` (`CleanupRow`) is
    /// the row's *top-level* view with a full-width `HStack` label — a materially
    /// different arrangement. Rather than depend on which nestings the platform
    /// happens to render an indicator for, the control is explicit: a `Button`
    /// whose label spans the row, a chevron this file draws and rotates, and
    /// expansion state the panel owns.
    ///
    /// **Why a disclosure rather than five more lines per row.** A real sweep on
    /// this machine is 477 artifacts; adding the whole chain to every row would
    /// turn a scannable list into a wall. Collapsed, the row is exactly as dense
    /// as it was. Expanded, MV-7 gets all three fields labelled in `codesign`'s
    /// own vocabulary, in the platform's own order, selectable — so comparing
    /// against `codesign -dv --verbose=4` is reading two copies of the same words
    /// rather than translating between two.
    ///
    /// Absent entirely for unsigned, invalid and could-not-assess artifacts:
    /// there is no identity to disclose, and an empty disclosure would suggest
    /// there is something behind it.
    @ViewBuilder
    private func signingIdentity(_ report: ArtifactIntegrityReport) -> some View {
        let fields = SecurityPresentation.identityFields(for: report.signature.signing)
        if fields.isEmpty == false {
            let package = report.location.packageID.name
            let isExpanded = expandedIdentities.contains(report.id)

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if isExpanded {
                        expandedIdentities.remove(report.id)
                    } else {
                        expandedIdentities.insert(report.id)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("Signing identity")
                        // Stretches the label to the full row width, so the
                        // click target is the whole line rather than the words.
                        Spacer(minLength: 0)
                    }
                    // Without this the transparent part of the HStack is not
                    // hit-testable and only the glyphs respond.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("security-integrity-\(package)-identity")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Signing identity for \(package)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Hides the signing fields" : "Shows the signing fields")

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(fields) { field in
                            LabeledContent(field.label) {
                                Text(field.value)
                                    .monospaced()
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier(
                                SecurityPresentation.identityFieldIdentifier(field, package: package)
                            )
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.top, 2)
                }
            }
            .font(.caption)
        }
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
