//
//  SecurityView.swift
//  cellar
//

import Catalog
import SecurityKit
import SwiftUI

/// Which finding the detail column is showing.
///
/// A package plus an advisory rather than a bare advisory ID: the same advisory
/// can apply to two installed packages, and they are two different rows.
struct SecurityFindingSelection: Hashable {
    let packageID: PackageID
    let advisoryID: String
}

/// Coverage, findings, and what nobody could answer.
///
/// The section order is **not decided here**. `SecurityPresentation.sections`
/// owns it, and `SecurityPresentation.headline` owns which sentence the summary
/// is entitled to say, because a rule inside a view body is a rule no test can
/// reach. This file owns symbols, layout and the accessibility identifiers the
/// projection hands it — and owns no claim about what is true.
struct SecurityView: View {
    let security: SecurityStore
    let consent: SecurityConsentPreference
    let credentials: any AdvisoryCredentialStoring
    @Binding var selection: SecurityFindingSelection?

    @State private var isDisclosing = false

    var body: some View {
        List(selection: $selection) {
            summary
            if consent.isGranted == false { consentCallToAction }
            ForEach(sections) { section in
                sectionView(section)
            }
        }
        .navigationTitle(AppSection.security.title)
        .overlay { emptyState }
        .toolbar { toolbar }
        .sheet(isPresented: $isDisclosing) {
            SecurityConsentSheet(consent: consent, credentials: credentials)
        }
    }

    // MARK: - Derived values

    private var state: SecurityScanState { security.state(for: .cveScan) }

    /// The result being shown, live or last-good. A failure must not empty the
    /// user's findings, so the stale one is shown rather than nothing.
    private var shownResult: SecurityScanResult? { state.result ?? state.staleResult }

    private var sections: [SecuritySection] {
        SecurityPresentation.sections(of: shownResult?.entries ?? [])
    }

    private var headline: SecurityHeadline {
        SecurityPresentation.headline(for: security.coverage(for: .cveScan))
    }

    // MARK: - Summary

    /// The one place a sentence about the whole inventory is allowed to appear,
    /// and it is a rendering of a value rather than a sentence written here.
    @ViewBuilder
    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline.title)
                    .font(.title3.weight(.semibold))
                Text(headline.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                freshness
                if state.failure != nil || security.scanStatus == .failed(.offline) {
                    degradation
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("security-summary")
        }
    }

    @ViewBuilder
    private var freshness: some View {
        if let entry = shownResult?.entries.first {
            Text(SecurityPresentation.freshnessLabel(entry.freshness, now: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("security-freshness")
        } else if security.isReady {
            Text("Nothing has been checked yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("security-freshness")
        }
    }

    /// A degraded scan says so next to the results it is degrading, not in an
    /// alert that steals the window. An unreachable network is an ordinary state
    /// here, not an error the user has to dismiss.
    @ViewBuilder
    private var degradation: some View {
        if let failure = state.failure {
            Label(Self.failureDescription(failure), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("security-degradation")
        }
    }

    @ViewBuilder
    private var consentCallToAction: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Advisory checking is off")
                    .font(.headline)
                Text(
                    """
                    Nothing has been sent from this Mac. Turn checking on to ask two advisory \
                    databases about the packages Cellar can map.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Review what would be sent…") { isDisclosing = true }
                    .accessibilityIdentifier("security-consent-open")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(_ section: SecuritySection) -> some View {
        Section {
            if section.items.isEmpty {
                // A zero count is a fact worth rendering. Hiding the empty section
                // is how "Not covered: 152" quietly disappears the moment the
                // vulnerable list happens to be empty.
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(section.items) { item in
                    rows(for: item)
                }
            }
        } header: {
            HStack {
                Text(section.title)
                Spacer(minLength: 8)
                Text("\(section.count)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier(section.identifier)
            .accessibilityLabel("\(section.title), \(section.count)")
        } footer: {
            Text(section.state.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func rows(for item: SecuritySectionItem) -> some View {
        switch item.state {
        case .vulnerable:
            ForEach(item.activeFindings) { finding in
                findingRow(finding, in: item)
            }
            if item.activeFindings.isEmpty, item.dismissedFindings.isEmpty == false {
                dismissedOnlyRow(item)
            }
        case .notCovered, .clean, .unavailable:
            packageRow(item)
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: VulnerabilityFinding, in item: SecuritySectionItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(item.packageID.name)
                    .font(.callout.weight(.medium))
                Text(finding.cveID ?? finding.advisoryID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                SeverityTag(tier: finding.severity)
            }
            Text(finding.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityIdentifier(SecurityPresentation.findingIdentifier(finding))
        .tag(SecurityFindingSelection(packageID: item.packageID, advisoryID: finding.advisoryID))
    }

    @ViewBuilder
    private func dismissedOnlyRow(_ item: SecuritySectionItem) -> some View {
        // Still in the Vulnerable section, still counted. Dismissal answers a
        // finding; it never changes what is known about the package.
        Text("\(item.packageID.name) — \(item.dismissedFindings.count) dismissed")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func packageRow(_ item: SecuritySectionItem) -> some View {
        HStack(spacing: 8) {
            Text(item.packageID.name)
                .font(.callout)
            Text(item.queriedVersion)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(Self.rowReason(item))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("security-package-\(item.packageID.kind.rawValue)-\(item.packageID.name)")
    }

    // MARK: - Empty state and toolbar

    /// Three different emptinesses. Only one of them is an answer.
    @ViewBuilder
    private var emptyState: some View {
        if sections.isEmpty {
            if security.isReady == false {
                ContentUnavailableView(
                    "Reading cached results",
                    systemImage: AppSection.security.systemImage
                )
            } else if consent.isGranted == false {
                ContentUnavailableView(
                    "Nothing checked",
                    systemImage: AppSection.security.systemImage,
                    description: Text(
                        """
                        Advisory checking is off, so nothing has been sent and nothing is known \
                        about these packages. This is not a clean result.
                        """
                    )
                )
            } else {
                ContentUnavailableView(
                    "No scan yet",
                    systemImage: AppSection.security.systemImage,
                    description: Text("Check now to ask about the packages Cellar can map.")
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("Check now") { Task { await security.scanNow() } }
                .disabled(consent.isGranted == false || isScanning)
                .accessibilityIdentifier("security-scan-now")
        }
        ToolbarItem {
            Button(consent.isGranted ? "Checking is on…" : "Checking is off…") { isDisclosing = true }
                .accessibilityIdentifier("security-consent")
        }
    }

    private var isScanning: Bool {
        switch security.scanStatus {
        case .discovering, .enriching: true
        case .idle, .blockedPendingConsent, .settled, .failed: false
        }
    }

    // MARK: - Vocabulary

    private static func rowReason(_ item: SecuritySectionItem) -> String {
        if let reason = item.notCoveredReason { return Self.reasonDescription(reason) }
        if let failure = item.failure { return Self.failureDescription(failure) }
        return "Checked, nothing reported"
    }

    static func reasonDescription(_ reason: NotCoveredReason) -> String {
        switch reason {
        case .unmapped: "Not in Cellar’s advisory mapping table"
        case .kindUnsupported: "Casks are not checked"
        case .unsupportedVersionScheme: "Version cannot be interpreted in this ecosystem"
        }
    }

    static func failureDescription(_ error: AdvisoryError) -> String {
        switch error {
        case .malformedPayload: "The database returned something Cellar could not read"
        case .malformedRecord: "This package’s record could not be read"
        case .offline: "No network was reachable"
        case .rateLimited: "The database refused on rate grounds"
        case .transportFailed: "The request failed"
        case .payloadTooLarge: "The response was too large to read"
        case .blockedPendingConsent: "Checking is off, so nothing was asked"
        }
    }
}

/// A severity tier as a tag. `unrated` renders as its own word rather than as an
/// absence, because "nobody scored this" is a fact and a blank is not.
private struct SeverityTag: View {
    let tier: SeverityTier

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityIdentifier("security-severity-\(tier.rawValue)")
    }

    private var label: String {
        switch tier {
        case .critical: "CRITICAL"
        case .high: "HIGH"
        case .medium: "MEDIUM"
        case .low: "LOW"
        case .none: "NONE"
        case .unrated: "UNRATED"
        }
    }
}
