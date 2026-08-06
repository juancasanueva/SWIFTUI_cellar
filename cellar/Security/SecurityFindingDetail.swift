//
//  SecurityFindingDetail.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SecurityKit
import SwiftUI

/// One advisory, framed as what it actually is.
///
/// Every sentence in this pane comes from a `SecurityPresentation` value rather
/// than being composed here — the "reported for" framing, the fix verdict, and
/// above all the upgrade note that must state plainly when Homebrew's version
/// differs from the advisory's fixed version. The view owns layout and symbols.
struct SecurityFindingDetail: View {
    let selection: SecurityFindingSelection?
    let security: SecurityStore
    let dismissals: DismissalStore
    let operations: OperationCenter
    let catalog: CatalogStore

    var body: some View {
        if let resolved {
            content(resolved.item, resolved.finding)
        } else {
            ContentUnavailableView(
                "No finding selected",
                systemImage: AppSection.security.systemImage,
                description: Text("Select an advisory to see what was reported and for what.")
            )
        }
    }

    // MARK: - Resolution

    private struct Resolved {
        let item: SecuritySectionItem
        let finding: VulnerabilityFinding
    }

    /// Resolved from the store on every render rather than captured at selection
    /// time, so a scan that lands mid-read replaces the finding instead of
    /// leaving a stale copy on screen — the `PackageDetailView` discipline.
    private var resolved: Resolved? {
        guard let selection else { return nil }
        let state = security.state(for: .cveScan)
        let entries = (state.result ?? state.staleResult)?.entries ?? []
        for item in SecurityPresentation.sections(of: entries).flatMap(\.items)
        where item.packageID == selection.packageID {
            if let finding = item.findings.first(where: { $0.advisoryID == selection.advisoryID }) {
                return Resolved(item: item, finding: finding)
            }
        }
        return nil
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ item: SecuritySectionItem, _ finding: VulnerabilityFinding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(item, finding)
                actions(item, finding)
                fixSection(finding)
                recordsSection(finding)
                provenanceSection(item)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(finding.cveID ?? finding.advisoryID)
    }

    @ViewBuilder
    private func header(_ item: SecuritySectionItem, _ finding: VulnerabilityFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.cveID ?? finding.advisoryID)
                .font(.largeTitle.weight(.semibold))
                .textSelection(.enabled)
            // Never "bat is vulnerable". The advisory is about an ecosystem
            // package that shares a name with a Homebrew formula, and saying
            // otherwise asserts something no database said.
            Text(SecurityPresentation.reportedFor(finding, queriedVersion: item.queriedVersion))
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("security-finding-framing")
            if finding.summary.isEmpty == false {
                Text(finding.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Severity", value: finding.severity.rawValue.uppercased())
            LabeledContent("Installed as", value: "\(item.packageID.name) \(item.queriedVersion)")
            if finding.aliases.isEmpty == false {
                LabeledContent("Also known as", value: finding.aliases.joined(separator: ", "))
            }
        }
    }

    @ViewBuilder
    private func actions(_ item: SecuritySectionItem, _ finding: VulnerabilityFinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                upgradeButton(item, finding)
                dismissalButton(item, finding)
                Spacer(minLength: 0)
            }
            if let note = offer(item, finding).note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("security-upgrade-note")
            }
        }
    }

    @ViewBuilder
    private func upgradeButton(_ item: SecuritySectionItem, _ finding: VulnerabilityFinding) -> some View {
        // The existing spine, unchanged: one `MutationCommand.upgrade` through
        // the existing centre. No new `BrewMutating` family exists for security.
        if let title = offer(item, finding).actionTitle,
           let target = PackageTarget(item.packageID) {
            Button(title) { operations.submit(.upgrade(target)) }
                .accessibilityIdentifier("security-upgrade-\(item.packageID.name)")
        }
    }

    @ViewBuilder
    private func dismissalButton(_ item: SecuritySectionItem, _ finding: VulnerabilityFinding) -> some View {
        let key = DismissalKey(
            advisoryID: finding.advisoryID,
            cveID: finding.cveID,
            packageID: item.packageID,
            installedVersion: item.queriedVersion
        )
        if dismissals.isDismissed(key) {
            Button("Undo dismissal") { dismissals.restore(key) }
                .accessibilityIdentifier("security-restore-\(finding.advisoryID)")
        } else {
            Button("Dismiss") { dismissals.dismiss(key) }
                .accessibilityIdentifier(SecurityPresentation.dismissIdentifier(finding))
        }
    }

    @ViewBuilder
    private func fixSection(_ finding: VulnerabilityFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fix")
                .font(.headline)
            Text(
                SecurityPresentation.fixDescription(
                    finding.fix,
                    declaredFixVersion: finding.declaredFixVersion
                )
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("security-fix-verdict")
        }
    }

    @ViewBuilder
    private func recordsSection(_ finding: VulnerabilityFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Records")
                .font(.headline)
            if let location = SecurityPresentation.advisoryRecordLocation(finding),
               let url = Self.browserURL(location) {
                Link(location, destination: url)
                    .accessibilityIdentifier("security-record-advisory")
            }
            if let location = SecurityPresentation.cveRecordLocation(finding),
               let url = Self.browserURL(location) {
                Link(location, destination: url)
                    .accessibilityIdentifier("security-record-cve")
            } else {
                Text("This advisory publishes no CVE alias, so there is no NVD record to link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func provenanceSection(_ item: SecuritySectionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Provenance")
                .font(.headline)
            Text(SecurityPresentation.freshnessLabel(item.freshness, now: .now))
                .accessibilityIdentifier("security-freshness")
            if let provenance = (security.state(for: .cveScan).result
                ?? security.state(for: .cveScan).staleResult)?.provenance {
                LabeledContent("Scanned", value: provenance.scannedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Mapping revision", value: "\(provenance.mappingRevision)")
                LabeledContent("Matcher version", value: "\(provenance.matcherVersion)")
                LabeledContent(
                    "Severity lookup",
                    value: provenance.enrichmentAttempted
                        ? (provenance.enrichmentSucceeded ? "Completed" : "Attempted, did not complete")
                        : "Not attempted"
                )
            }
        }
        .font(.callout)
        .accessibilityIdentifier("security-provenance")
    }

    // MARK: - Helpers

    private func offer(
        _ item: SecuritySectionItem,
        _ finding: VulnerabilityFinding
    ) -> SecurityUpgradeOffer {
        SecurityPresentation.upgradeOffer(
            for: finding,
            catalogVersion: catalog.package(item.packageID)?.version
        )
    }

    /// Adds the scheme `SecurityKit` deliberately does not carry.
    ///
    /// The library returns a schemeless location so its exact two-host egress
    /// guard stays an equality rather than an allow-list; a link a person opens
    /// in a browser is a presentation concern and lives here.
    private static func browserURL(_ location: String) -> URL? {
        URL(string: "https://" + location)
    }
}
