//
//  SecurityView.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SecurityKit
import SwiftUI

/// Which finding the detail sheet is showing.
///
/// A package plus an advisory rather than a bare advisory ID: the same advisory
/// can apply to two installed packages, and they are two different rows.
struct SecurityFindingSelection: Hashable, Identifiable {
    let packageID: PackageID
    let advisoryID: String

    var id: String { "\(packageID.kind.rawValue)/\(packageID.name)/\(advisoryID)" }
}

/// Coverage, findings, and what nobody could answer — as one full-width
/// dashboard, the Health section's shape.
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
    /// The finding sheet's dependencies — the pane that used to live in the
    /// detail column now opens on demand.
    let dismissals: DismissalStore
    let operations: OperationCenter
    let catalog: CatalogStore
    /// The integrity half, embedded as the dashboard's last section rather
    /// than squatting in a detail column it rarely filled.
    let integrity: ArtifactIntegrityStore
    let artifactLocations: [ArtifactLocation]

    @State private var isDisclosing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if consent.isGranted == false { consentCard }
                // Before the coverage lists, not after: "Not covered" alone can
                // run to a hundred-plus rows, and a peer check with its own run
                // button must not need scrolling past them to be found.
                ArtifactIntegritySection(store: integrity, locations: artifactLocations)
                if sections.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        sectionCard(section)
                    }
                }
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 34, trailing: 30))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
        .sheet(isPresented: $isDisclosing) {
            SecurityConsentSheet(consent: consent, credentials: credentials)
        }
        .sheet(item: $selection) { finding in
            findingSheet(finding)
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

    // MARK: - Hero

    /// The one place a sentence about the whole inventory is allowed to appear,
    /// and it is a rendering of a value rather than a sentence written here.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline.title)
                .font(.system(size: 23, weight: .semibold))
                .kerning(-0.5)
                .foregroundStyle(Theme.textPrimary)
            Text(headline.message)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Color.white.opacity(0.52))
                .frame(maxWidth: 680, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            freshness
            if state.failure != nil || security.scanStatus == .failed(.offline) {
                degradation
            }
            HStack(spacing: 8) {
                Button("Check now") { Task { await security.scanNow() } }
                    .buttonStyle(ActionPillStyle())
                    .disabled(consent.isGranted == false || isScanning)
                    .accessibilityIdentifier("security-scan-now")
                Button(consent.isGranted ? "Checking is on…" : "Checking is off…") {
                    isDisclosing = true
                }
                .buttonStyle(ActionPillStyle())
                .accessibilityIdentifier("security-consent")
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("security-summary")
    }

    @ViewBuilder
    private var freshness: some View {
        if let entry = shownResult?.entries.first {
            Text(SecurityPresentation.freshnessLabel(entry.freshness, now: .now))
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityIdentifier("security-freshness")
        } else if security.isReady {
            Text("Nothing has been checked yet.")
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textTertiary)
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
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
                .accessibilityIdentifier("security-degradation")
        }
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advisory checking is off")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(
                """
                Nothing has been sent from this Mac. Turn checking on to ask two advisory \
                databases about the packages Cellar can map.
                """
            )
            .font(.system(size: 12))
            .lineSpacing(3)
            .foregroundStyle(Color.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
            Button("Review what would be sent…") { isDisclosing = true }
                .buttonStyle(ActionPillStyle())
                .padding(.top, 2)
                .accessibilityIdentifier("security-consent-open")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .themeCard(radius: 10)
    }

    // MARK: - Coverage sections

    private func sectionCard(_ section: SecuritySection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(section.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text("\(section.count)")
                    .font(Theme.mono(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityIdentifier(section.identifier)
            .accessibilityLabel("\(section.title), \(section.count)")
            Text(section.state.explanation)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Color.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            if section.items.isEmpty {
                // A zero count is a fact worth rendering. Hiding the empty section
                // is how "Not covered: 152" quietly disappears the moment the
                // vulnerable list happens to be empty.
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.top, 12)
            } else {
                ForEach(section.items) { item in
                    HairlineDivider()
                        .padding(.vertical, 10)
                    rows(for: item)
                }
            }
        }
        .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .themeCard(radius: 10)
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

    /// A vulnerable row opens the finding sheet — the occasional need the
    /// retired detail column used to hold permanently.
    private func findingRow(_ finding: VulnerabilityFinding, in item: SecuritySectionItem) -> some View {
        Button {
            selection = SecurityFindingSelection(packageID: item.packageID, advisoryID: finding.advisoryID)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.packageID.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(finding.cveID ?? finding.advisoryID)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    SeverityTag(tier: finding.severity)
                }
                Text(finding.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(SecurityPresentation.findingIdentifier(finding))
    }

    @ViewBuilder
    private func dismissedOnlyRow(_ item: SecuritySectionItem) -> some View {
        // Still in the Vulnerable section, still counted. Dismissal answers a
        // finding; it never changes what is known about the package.
        Text("\(item.packageID.name) — \(item.dismissedFindings.count) dismissed")
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.5))
    }

    @ViewBuilder
    private func packageRow(_ item: SecuritySectionItem) -> some View {
        HStack(spacing: 8) {
            Text(item.packageID.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
            Text(item.queriedVersion)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(Self.rowReason(item))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("security-package-\(item.packageID.kind.rawValue)-\(item.packageID.name)")
    }

    // MARK: - Finding sheet

    private func findingSheet(_ finding: SecurityFindingSelection) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button("Done") { selection = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
            SecurityFindingDetail(
                selection: finding,
                security: security,
                dismissals: dismissals,
                operations: operations,
                catalog: catalog
            )
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 460, idealHeight: 560)
        .background(Theme.windowBackground)
    }

    // MARK: - Empty state

    /// Three different emptinesses. Only one of them is an answer.
    @ViewBuilder
    private var emptyState: some View {
        Group {
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
        .frame(maxWidth: .infinity, minHeight: 220)
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

/// A severity tier as a tag, in the design's tones. `unrated` renders as its
/// own word rather than as an absence, because "nobody scored this" is a fact
/// and a blank is not.
private struct SeverityTag: View {
    let tier: SeverityTier

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
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

    private var color: Color {
        switch tier {
        case .critical, .high: Theme.dangerText
        case .medium: .orange
        case .low, .none, .unrated: Color.white.opacity(0.5)
        }
    }

    private var fill: Color {
        switch tier {
        case .critical, .high: Theme.dangerTint(0.16)
        case .medium: Color.orange.opacity(0.14)
        case .low, .none, .unrated: Theme.controlFill
        }
    }
}
