//
//  HealthComposition.swift
//  cellar
//

import BrewClient
import Catalog
import DiskUsage
import Foundation
import SecurityKit

/// One input's answer plus the sentence a row renders for it.
///
/// Two fields rather than one because `Catalog` computes over the normalised
/// health alone and has no idea what a byte, a keg or a CVE is (design HD6). The
/// measurement is app-authored text, and it is carried **only** where the signal
/// was answered — so a count can never outlive the answer it came from.
nonisolated struct HealthReading: Sendable, Hashable {
    let signal: HealthSignal
    let measurement: HealthMeasurement?

    static func unknown(_ reason: HealthUnknownReason) -> HealthReading {
        HealthReading(signal: .unknown(reason), measurement: nil)
    }

    static func answered(
        _ health: Double,
        _ summary: String,
        unanswered: HealthUnknownReason? = nil
    ) -> HealthReading {
        HealthReading(
            signal: .answered(health),
            measurement: HealthMeasurement(summary: summary, unanswered: unanswered)
        )
    }
}

/// Translates what the app already holds into the eight scalars the score is a
/// function of.
///
/// This is the whole reason `Catalog` can stay dependency-free: every foreign
/// type — `DoctorOutcome`, `CoverageTotals`, `SecurityScanState`,
/// `CleanupOrphans`, `CleanupReportedTotal`, `DiskUsageSnapshot`/`DiskRootState`,
/// `InstalledBrowse`, `HomebrewLastUpdate` — is read here and nowhere else, and
/// the score never learns any of their names.
///
/// **The one rule every mapping below obeys**: a value that means "nobody could
/// answer" becomes `.unknown(reason)`. Never `.answered(1.0)`. Every one of these
/// shapes reads like good news when it is mapped carelessly — `notCovered` looks
/// like zero vulnerabilities, an unmeasured disk looks like an empty cache, a
/// doctor nobody ran looks like a doctor that found nothing — and a single number
/// is the one surface where the user cannot see the substitution.
///
/// Pure and `nonisolated`: no store, no clock read, no seam. `now` is a parameter
/// because a reading's age is a fact about two moments, and inventing one of them
/// inside a mapping would make the whole thing untestable.
nonisolated enum HealthComposition {

    // MARK: - The eight mappings

    /// Outdated is measured against the inventory the user can actually see, so
    /// the number matches the Installed list's own count including its snooze
    /// narrowing.
    static func outdated(browse: InstalledBrowse, metadata: MetadataLookup?) -> HealthReading {
        guard browse.isAvailable else { return .unknown(.unavailable) }
        let installed = browse.inventory.packages.count
        // An inventory that has not loaded is not an inventory with nothing wrong
        // with it.
        guard installed > 0 else { return .unknown(.unmeasured) }

        let outdated = browse.outdatedIDs(metadata: metadata).count
        return .answered(
            HealthThresholds.outdatedHealth(outdated: outdated, installed: installed),
            HealthCopy.outdatedSummary(outdated: outdated, installed: installed)
        )
    }

    /// A vulnerability count is only a count *of* something — the packages an
    /// advisory source actually answered for.
    static func vulnerable(state: SecurityScanState, totals: CoverageTotals) -> HealthReading {
        if let reason = scanGap(state) { return .unknown(reason) }
        guard totals.total > 0 else { return .unknown(.unmeasured) }

        let answered = totals.vulnerable + totals.clean
        let unanswered = totals.notCovered + totals.unavailable
        // Nothing answered at all is not "no vulnerabilities" — it is the exact
        // substitution `CoverageTotals`' own doc comment exists to prevent.
        guard answered > 0 else { return .unknown(.notCovered) }

        return .answered(
            HealthThresholds.vulnerableHealth(vulnerable: totals.vulnerable, answered: answered),
            HealthCopy.vulnerableSummary(
                vulnerable: totals.vulnerable,
                answered: answered,
                unanswered: unanswered
            ),
            unanswered: unanswered > 0 || isPartialScan(state) ? .partial : nil
        )
    }

    /// Coverage is scored in its own right — the M4 lesson given a weight, so an
    /// unanswered inventory costs points instead of being invisible.
    static func advisoryCoverage(state: SecurityScanState, totals: CoverageTotals) -> HealthReading {
        if let reason = scanGap(state) { return .unknown(reason) }
        guard totals.total > 0 else { return .unknown(.unmeasured) }

        let answered = totals.vulnerable + totals.clean
        return .answered(
            HealthThresholds.advisoryCoverageHealth(answered: answered, total: totals.total),
            HealthCopy.coverageSummary(answered: answered, total: totals.total)
        )
    }

    /// Absent, unreadable and future-dated reach the score as themselves. A
    /// future-dated marker is deliberately not clamped: clamping would render a
    /// wrong clock as a perfectly fresh installation.
    static func lastUpdate(_ reading: HomebrewLastUpdate?, now: Date) -> HealthReading {
        switch reading {
        case .none:
            return .unknown(.unmeasured)
        case .absent:
            return .unknown(.absent)
        case .unreadable:
            return .unknown(.unreadable)
        case .futureDated:
            return .unknown(.futureDated)
        case .read(let date):
            let age = max(0, now.timeIntervalSince(date))
            return .answered(
                HealthThresholds.lastUpdateHealth(age: age),
                HealthCopy.lastUpdateSummary(days: Int(age / 86_400))
            )
        }
    }

    static func orphans(_ orphans: CleanupOrphans?) -> HealthReading {
        switch orphans {
        // No preview has run, so nothing is known — which is a different fact
        // from "brew reported none".
        case .none, .notApplicable: .unknown(.unmeasured)
        case .unknown: .unknown(.unknown)
        case .known(_, let reportedCount, _):
            .answered(
                HealthThresholds.orphansHealth(count: reportedCount),
                HealthCopy.orphansSummary(count: reportedCount)
            )
        }
    }

    /// Every keg past the first, across the whole Cellar.
    static func duplicateVersions(_ snapshot: DiskUsageSnapshot?) -> HealthReading {
        guard let snapshot else { return .unknown(.unmeasured) }
        if case .failed = snapshot.rootStates[.cellar] { return .unknown(.failed) }

        let extras = snapshot.packages.reduce(0) { $0 + max(0, $1.versions.count - 1) }
        return .answered(
            HealthThresholds.duplicateVersionsHealth(count: extras),
            HealthCopy.duplicateVersionsSummary(count: extras, incomplete: !snapshot.isComplete),
            unanswered: snapshot.isComplete ? nil : .partial
        )
    }

    /// The cache size, from the disk measurement when there is one and from the
    /// cleanup preview's reported footer when there is not.
    ///
    /// Two sources for one row because they answer at different times: the disk
    /// scan is the authority and runs on its own cadence, while a cleanup preview
    /// the user already asked for carries a reclaimable total that is better than
    /// nothing. Neither invents a number, and `.unknown` on both is unknown.
    static func cache(snapshot: DiskUsageSnapshot?, reclaimable: CleanupReportedTotal?) -> HealthReading {
        let reclaimableBytes: Int64? = {
            guard case .reportedFooter(let bytes) = reclaimable else { return nil }
            return bytes
        }()

        guard let snapshot else {
            guard let reclaimableBytes else {
                return .unknown(reclaimable == .unknown ? .unknown : .unmeasured)
            }
            return .answered(
                HealthThresholds.cacheHealth(bytes: reclaimableBytes),
                HealthCopy.cacheSummary(bytes: reclaimableBytes, reclaimable: nil, incomplete: false)
            )
        }
        if case .failed = snapshot.rootStates[.cache] { return .unknown(.failed) }

        let bytes = snapshot.cache.allocatedBytes
        return .answered(
            HealthThresholds.cacheHealth(bytes: bytes),
            HealthCopy.cacheSummary(
                bytes: bytes,
                reclaimable: reclaimableBytes,
                incomplete: !snapshot.isComplete
            ),
            unanswered: snapshot.isComplete ? nil : .partial
        )
    }

    /// A doctor nobody ran is not a doctor that found nothing.
    static func doctor(_ outcome: DoctorOutcome?) -> HealthReading {
        switch outcome {
        case .none:
            return .unknown(.notRun)
        case .unavailable(let reason):
            switch reason {
            case .cancelled: return .unknown(.cancelled)
            case .signalled: return .unknown(.failed)
            case .brewUnavailable, .launchFailed: return .unknown(.unavailable)
            }
        case .clean(let evidence), .issues(let evidence):
            return .answered(
                HealthThresholds.doctorHealth(warnings: evidence.warningCount),
                HealthCopy.doctorSummary(warnings: evidence.warningCount, partial: evidence.isPartial),
                unanswered: evidence.isPartial ? .partial : nil
            )
        }
    }

    // MARK: - Assembling the one value the score is a function of

    // swiftlint:disable:next function_parameter_count
    static func inputs(
        browse: InstalledBrowse,
        metadata: MetadataLookup?,
        scan: SecurityScanState,
        coverage: CoverageTotals,
        orphans cleanupOrphans: CleanupOrphans?,
        reclaimable: CleanupReportedTotal?,
        snapshot: DiskUsageSnapshot?,
        lastUpdate reading: HomebrewLastUpdate?,
        doctor outcome: DoctorOutcome?,
        now: Date
    ) -> HealthInputs {
        let readings: [HealthInput: HealthReading] = [
            .outdated: outdated(browse: browse, metadata: metadata),
            .vulnerable: vulnerable(state: scan, totals: coverage),
            .advisoryCoverage: advisoryCoverage(state: scan, totals: coverage),
            .lastUpdate: lastUpdate(reading, now: now),
            .orphans: orphans(cleanupOrphans),
            .duplicateVersions: duplicateVersions(snapshot),
            .cache: cache(snapshot: snapshot, reclaimable: reclaimable),
            .doctor: doctor(outcome)
        ]

        return HealthInputs(
            readings.mapValues(\.signal),
            measurements: readings.compactMapValues(\.measurement)
        )
    }

    // MARK: - Remediation, mapped to verbs other capabilities already ship

    /// What a health row's remediation actually submits.
    ///
    /// A closed set over verbs that already exist elsewhere. This capability
    /// introduces no new mutating verb: there is no `brew doctor --fix`, and
    /// `brew update` is a `.mutate` PRD §3.4 does not list among the dashboard's
    /// actions, so `.lastUpdate` and `.vulnerable` offer `.none` rather than
    /// something invented for the occasion.
    enum Command: Sendable, Equatable {
        case mutation(MutationCommand)
        case cleanup(CleanupCommand)
        /// Not a mutation at all — the same read the section already owns.
        case runDoctor
    }

    static func command(for remediation: HealthRemediation) -> Command? {
        switch remediation {
        case .upgradeAll: .mutation(.upgradeAll)
        case .autoremove: .cleanup(CleanupCommand(scope: .autoremove))
        case .cleanupCache: .cleanup(CleanupCommand(scope: .global))
        case .runDoctor: .runDoctor
        case .none: nil
        }
    }

    // MARK: -

    /// The reason a scan state cannot answer at all, or `nil` when it can.
    ///
    /// `.partial` is deliberately absent: a partial scan *has* an answer and a
    /// gap, and reporting only the gap would throw away findings the scan really
    /// did make.
    private static func scanGap(_ state: SecurityScanState) -> HealthUnknownReason? {
        switch state {
        case .idle: .unmeasured
        case .loading(let stale): stale == nil ? .unmeasured : nil
        case .failed: .failed
        case .cancelled: .cancelled
        case .content, .partial: nil
        }
    }

    private static func isPartialScan(_ state: SecurityScanState) -> Bool {
        if case .partial = state { return true }
        return state.result?.isPartial ?? false
    }
}
