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
    /// Read for two values and nothing else: whether npm is contributing at all,
    /// and how current its answer is. The section still acquires nothing — both
    /// are resident state, exactly like the six signals above.
    let npmDetection: NpmDetectionStore
    let npm: NpmStore
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
    /// The weights table, shown on demand from the score's "?" — the surface
    /// that makes the number arguable moved from a fixed rail to a popover.
    @State private var isBreakdownPresented = false

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                score
                HairlineDivider()
                    .padding(.top, 26)
                controls
                    .padding(.top, 24)
                rows
                    .padding(.top, 26)
            }
            .padding(EdgeInsets(top: 30, leading: 34, bottom: 40, trailing: 34))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.windowBackground)
        .task(id: inputs) {
            await health.project(inputs, now: now)
        }
    }

    // MARK: - The number, never without its caveat

    @ViewBuilder
    private var score: some View {
        let presentation = HealthScorePresentation(health.content?.score ?? .unscorable(unknownInputs: []))
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(HealthCopy.heroTitle)
                    .font(.system(size: 30, weight: .bold))
                    .kerning(-0.8)
                    .foregroundStyle(Theme.textPrimary)
                if presentation.isScored == false {
                    Text(presentation.headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textBody)
                        .accessibilityIdentifier("health-score")
                }
                if let caveat = presentation.caveat {
                    Text(caveat)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(maxWidth: 620, alignment: .leading)
                        .accessibilityIdentifier("health-score-caveat")
                }
                if let answeredWeight = presentation.answeredWeight {
                    Text(answeredWeight)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if presentation.isScored, let value = Int(presentation.headline) {
                HealthScoreRing(value: value, headline: presentation.headline)
                    .padding(.top, 4)
            }
            breakdownButton
        }
    }

    /// The "?" beside the score, and the only way into the weights table.
    /// Rendered even while unscorable: the panel then says what was missing,
    /// which is exactly when the number needs arguing with.
    private var breakdownButton: some View {
        Button {
            isBreakdownPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(HealthCopy.breakdownTitle)
        .accessibilityLabel(HealthCopy.breakdownTitle)
        .accessibilityIdentifier("health-breakdown-toggle")
        .popover(isPresented: $isBreakdownPresented, arrowEdge: .bottom) {
            HealthBreakdownPanel(health: health)
                .frame(width: 420, height: 460)
                .background(Theme.windowBackground)
        }
    }

    // MARK: - The two acquisitions, both behind a control

    private var controls: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(HealthCopy.quickActionsTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 9) {
                actionChip(
                    HealthCopy.runDoctorTitle,
                    command: HealthCopy.runDoctorCommand,
                    identifier: "health-run-doctor",
                    action: runDoctor
                )
                .disabled(health.isRunningDoctor || brewDetection.state.installation == nil)

                actionChip(
                    HealthCopy.readLastUpdateTitle,
                    command: nil,
                    identifier: "health-read-last-update",
                    action: readHomebrewAge
                )
                Spacer(minLength: 0)
            }
        }
        .help(HealthCopy.runDoctorExplanation)
    }

    private func actionChip(
        _ label: String,
        command: String?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                if let command {
                    // Inherits the pill's tint rather than naming a colour, so
                    // the de-emphasis survives the disabled dim too.
                    Text(command)
                        .font(Theme.mono(10.5))
                        .opacity(0.55)
                }
            }
        }
        .buttonStyle(ActionPillStyle())
        .accessibilityIdentifier(identifier)
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
        VStack(alignment: .leading, spacing: 11) {
            Text(HealthCopy.rowsTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 0) {
                let content = health.content?.rows ?? []
                ForEach(content, id: \.input) { row in
                    HealthRowView(
                        row: row,
                        remediate: HealthComposition.command(for: row.remediation).map { command in
                            { remediate(command) }
                        },
                        isRemediationEnabled: operations.isAvailable,
                        warnings: row.input == .doctor ? health.doctor?.evidence?.warnings ?? [] : []
                    )
                    .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .background(Theme.rowFill)
                    if row.input != content.last?.input {
                        Rectangle().fill(Theme.separator).frame(height: 0.5)
                    }
                }
            }
            .themeCard(fill: Theme.rowFill, radius: 10)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityIdentifier("health-rows")
    }

    // MARK: - Remediation travels the owning capability's own spine

    /// Nothing new is constructed here, and no confirmation is skipped.
    ///
    /// Upgrade-all is submitted the same way the Installed list submits it:
    /// through the centre's ask-first `submitUpgradeAll()`, so the same
    /// Upgrade-everything confirmation appears here (bulk-confirmation ruling
    /// 2026-09-01). Cleanup and autoremove go through the **shipped**
    /// preview-then-review sequence, so the confirmation that appears is
    /// `CleanupConfirmationDisclosure` carrying the same evidence it carries on
    /// the Cleanup surface — a health row cannot present a weaker disclosure,
    /// because it does not build one.
    private func remediate(_ command: HealthComposition.Command) {
        switch command {
        case .upgradeAll:
            operations.submitUpgradeAll()
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
            browse: InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)
                .withNpmSource(NpmSourceAvailability(npmDetection.state)),
            metadata: metadata.availability.isAvailable ? metadata.snapshot.lookup : nil,
            scan: security.state(for: .cveScan),
            coverage: security.coverage(for: .cveScan),
            orphans: cleanup.state(for: .autoremove).result?.evidence.orphans,
            reclaimable: cleanup.state(for: .global).result?.evidence.total,
            snapshot: diskUsage.visibleSnapshot,
            lastUpdate: health.lastUpdate,
            doctor: health.doctor,
            now: now,
            npmFreshness: npm.inventory.outdated
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
