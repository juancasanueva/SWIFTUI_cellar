//
//  HealthView.swift
//  cellar
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Persistence
import SecurityKit
import SwiftUI

/// One number over eight signals, and everything it could not answer.
///
/// **Rendering this section acquires nothing.** Six of the eight inputs are
/// resident state some other store already owns — the inventory, security
/// coverage, cleanup orphans, the disk measurement — and reading them here
/// triggers no sync, no scan, no measurement and no refresh. The two this
/// capability owns are the doctor run, which happens only when the button is
/// pressed, and the last-update reading, which is one file's modification date
/// behind a seam and costs no process at all.
///
/// The only `.task` here rebuilds the **pure** projection when the inputs change.
/// It reaches no seam: `HealthProjection.build` takes one value and a date, so
/// there is nothing in its scope to trigger.
///
/// Every string comes from `HealthCopy`. This view owns layout and identifiers.
struct HealthView: View {
    let health: HealthStore
    let brewDetection: BrewDetectionStore
    let installed: InstalledStore
    let metadata: MetadataStore
    let security: SecurityStore
    let cleanup: CleanupStore
    let diskUsage: DiskUsageStore
    let operations: OperationCenter

    /// The moment the ages on this screen are measured against.
    ///
    /// Held rather than read per render, for a reason the alternative makes
    /// obvious: a `Date()` inside `inputs` would change on every pass, so the
    /// `.task(id:)` below would rebuild the projection continuously and the
    /// section would become the polling loop this capability forbids.
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                score
                controls
                rows
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(AppSection.health.title)
        .task(id: inputs) {
            await health.project(inputs, now: now)
        }
    }

    // MARK: - The number, never without its caveat

    @ViewBuilder
    private var score: some View {
        let presentation = HealthScorePresentation(health.content?.score ?? .unscorable(unknownInputs: []))
        VStack(alignment: .leading, spacing: 4) {
            Text(HealthCopy.scoreTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(presentation.headline)
                .font(presentation.isScored ? .system(size: 44, weight: .semibold) : .title3)
                .monospacedDigit()
                .accessibilityIdentifier("health-score")
            if let caveat = presentation.caveat {
                Text(caveat)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("health-score-caveat")
            }
            if let answeredWeight = presentation.answeredWeight {
                Text(answeredWeight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - The two acquisitions, both behind a control

    private var controls: some View {
        HStack(spacing: 8) {
            Button(HealthCopy.runDoctorTitle, action: runDoctor)
                .disabled(health.isRunningDoctor || brewDetection.state.installation == nil)
                .accessibilityIdentifier("health-run-doctor")

            Button(HealthCopy.readLastUpdateTitle, action: readHomebrewAge)
                .accessibilityIdentifier("health-read-last-update")

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .help(HealthCopy.runDoctorExplanation)
    }

    /// The one acquisition that spawns, and it spawns only from here.
    private func runDoctor() {
        guard let installation = brewDetection.state.installation else { return }
        Task { await health.runDoctor(using: installation) }
    }

    private func readHomebrewAge() {
        now = Date()
        guard let roots = homebrewRoots else { return }
        health.readLastUpdate(roots: roots, now: now)
    }

    // MARK: - Seven rows

    @ViewBuilder
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(HealthCopy.rowsTitle)
                .font(.headline)
            ForEach(health.content?.rows ?? [], id: \.input) { row in
                Divider()
                HealthRowView(
                    row: row,
                    remediate: HealthComposition.command(for: row.remediation).map { command in
                        { remediate(command) }
                    },
                    isRemediationEnabled: operations.isAvailable
                )
            }
        }
        .accessibilityIdentifier("health-rows")
    }

    // MARK: - Remediation travels the owning capability's own spine

    /// Nothing new is constructed here, and no confirmation is skipped.
    ///
    /// Upgrade-all is submitted the same way the Installed list submits it.
    /// Cleanup and autoremove go through the **shipped** preview-then-review
    /// sequence, so the confirmation that appears is `CleanupConfirmationDisclosure`
    /// carrying the same evidence it carries on the Cleanup surface — a health row
    /// cannot present a weaker disclosure, because it does not build one.
    private func remediate(_ command: HealthComposition.Command) {
        switch command {
        case .mutation(let mutation):
            operations.submit(mutation)
        case .cleanup(let cleanupCommand):
            review(cleanupCommand.scope)
        case .runDoctor:
            runDoctor()
        }
    }

    /// Reviews a current preview, or takes one first.
    ///
    /// `requestCleanup` deliberately answers `nil` for anything but current,
    /// complete, non-empty evidence, so a stale or absent preview measures again
    /// rather than confirming against something nobody looked at.
    private func review(_ scope: CleanupScope) {
        if operations.requestCleanup(preview: cleanup.state(for: scope)) != nil { return }
        cleanup.startPreview(
            scope: scope,
            for: brewDetection.state,
            diskUsage: diskUsage.visibleSnapshot.map {
                CleanupDiskUsageContext(snapshot: $0, expectedRoots: $0.roots)
            }
        )
    }

    // MARK: - The eight inputs, read from state the app already holds

    private var inputs: HealthInputs {
        HealthComposition.inputs(
            browse: InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil),
            metadata: metadata.availability.isAvailable ? metadata.snapshot.lookup : nil,
            scan: security.state(for: .cveScan),
            coverage: security.coverage(for: .cveScan),
            orphans: cleanup.state(for: .autoremove).result?.evidence.orphans,
            reclaimable: cleanup.state(for: .global).result?.evidence.total,
            snapshot: diskUsage.visibleSnapshot,
            lastUpdate: health.lastUpdate,
            doctor: health.doctor,
            now: now
        )
    }

    private var homebrewRoots: HomebrewRoots? {
        guard let installation = brewDetection.state.installation else { return nil }
        return HomebrewRoots(
            installation: installation,
            userCacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        )
    }
}
