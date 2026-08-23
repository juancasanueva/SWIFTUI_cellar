import BrewClient
import Catalog
import SwiftUI

struct TapDetailView: View {
    let taps: TapStore
    let installed: InstalledStore
    let operations: OperationCenter
    let tapName: String?
    let currentForceEvidence: @MainActor @Sendable (TapName) -> ForceUntapEvidence?
    let showInInstalled: @MainActor (PackageID) -> Void

    @State private var query = ""
    @State private var kind: PackageKind?
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Group {
            if let tap {
                VStack(alignment: .leading, spacing: 0) {
                    header(tap)
                    HairlineDivider()
                    filterBar
                    HairlineDivider()
                    packageList(for: tap)
                    HairlineDivider()
                    footer(tap)
                }
            } else {
                ContentUnavailableView(
                    "No tap selected",
                    systemImage: AppSection.taps.systemImage,
                    description: Text("Choose a third-party tap to inspect its packages.")
                )
            }
        }
        .navigationTitle(tap?.name ?? AppSection.taps.title)
    }

    /// The identity row every detail pane shares — tile, name, story line and
    /// the pane's verbs — in `PackageDetailView.header`'s exact dimensions.
    private func header(_ tap: TapRecord) -> some View {
        HStack(alignment: .top, spacing: 18) {
            PackageTile(name: tap.name, size: 72, fontSize: 27, cornerRadius: 17)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Text(tap.name)
                        .font(.system(size: 23, weight: .semibold))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                    // Same projection as the list row, by construction (TM12).
                    if let badge = TapProjection.trust(for: tap).badge {
                        TapTrustBadge(text: badge, identifier: "tap-detail-trust-badge")
                    }
                }
                HStack(spacing: 9) {
                    Text(TapProjection.packageSummary(for: tap))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                    Text("Third-party tap")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 12)
            // TM12 :421-430 — badge and controls come from one projection, so
            // the row and this header cannot drift, and an `unreported` tap
            // reaches neither branch and therefore builds nothing.
            if TapProjection.trust(for: tap).canGrant {
                Button("Trust") { grantTrust(tap) }
                    .buttonStyle(TapActionButtonStyle(
                        fill: Theme.controlFillLoud,
                        text: Theme.textPrimary
                    ))
                    .disabled(!operations.isAvailable)
                    .accessibilityIdentifier("tap-trust-button")
                    .padding(.top, 6)
            }
            if TapProjection.trust(for: tap).canRevoke {
                Button("Untrust") { revokeTrust(tap) }
                    .buttonStyle(TapActionButtonStyle(
                        fill: Theme.controlFill,
                        text: Theme.textPrimary
                    ))
                    .disabled(!operations.isAvailable)
                    .accessibilityIdentifier("tap-untrust-button")
                    .padding(.top, 6)
            }
            Button("Untap") { untap(tap) }
                .buttonStyle(TapActionButtonStyle(
                    fill: Theme.dangerTint(0.12),
                    text: Theme.dangerText,
                    stroke: Theme.dangerTint(0.3)
                ))
                .disabled(!operations.isAvailable)
                .accessibilityIdentifier("tap-untap-button")
                .padding(.top, 6)
            if let name = TapName(tap.name), currentForceEvidence(name) != nil {
                Button("Force Untap", role: .destructive) { requestForceUntap(name) }
                    .buttonStyle(TapActionButtonStyle(
                        fill: Theme.dangerTint(0.22),
                        text: Theme.dangerText,
                        stroke: Theme.dangerTint(0.4)
                    ))
                    .disabled(!operations.isAvailable)
                    .accessibilityIdentifier("tap-force-untap-button")
                    .padding(.top, 6)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 30, bottom: 18, trailing: 30))
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Text("Packages")
                .font(.system(size: 17, weight: .semibold))
                .kerning(-0.3)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            TextField("Filter packages", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 27, alignment: .leading)
                .frame(maxWidth: 220)
                .background(
                    Theme.controlFill,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .accessibilityIdentifier("tap-package-filter")
            HStack(spacing: 5) {
                FilterChip(label: "All", isOn: kind == nil) {
                    kind = nil
                }
                FilterChip(label: "Formulae", isOn: kind == .formula) {
                    kind = .formula
                }
                FilterChip(label: "Casks", isOn: kind == .cask) {
                    kind = .cask
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 30, bottom: 12, trailing: 30))
    }

    private func packageList(for tap: TapRecord) -> some View {
        List(filteredPackages(for: tap)) { package in
            HStack(spacing: 10) {
                Circle()
                    .fill(package.isInstalled ? Theme.successBase : Color.white.opacity(0.22))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(package.displayName)
                            .font(Theme.mono(12.5))
                            .foregroundStyle(Theme.textPrimary)
                        kindBadge(package.id.kind)
                    }
                    if let explanation = package.statusExplanation {
                        Text(explanation)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                }
                Spacer(minLength: 12)
                if let installedID = package.installedHandoff {
                    Button("Show in Installed") { showInInstalled(installedID) }
                        .buttonStyle(ActionPillStyle())
                }
            }
            // Leading 14 on top of the native row inset lands the status dot
            // on the pane's 30pt gutter, in line with the Packages heading.
            .padding(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 0))
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("tap-package-list")
    }

    private func kindBadge(_ kind: PackageKind) -> some View {
        Text(kind == .formula ? "FORMULA" : "CASK")
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(kind == .cask ? Theme.caskText : Theme.infoText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                kind == .cask ? Theme.caskTint(0.18) : Theme.infoTint(0.15),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }

    private func footer(_ tap: TapRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let remote = tap.remote {
                metaRow("Repository") {
                    Link(remote.absoluteString, destination: remote)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(theme.base)
                        .lineLimit(1)
                }
            }
            if let lastCommit = tap.lastCommit {
                metaRow("Last commit") {
                    Text(lastCommit)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.textMono)
                }
            }
            if TapProjection.trust(for: tap).canGrant {
                Text("Homebrew withholds which packages came from this tap while it is untrusted, so Force Untap is unavailable. Trust the tap to see them, or use Untap.")
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tap-withheld-footer")
            }
            Text("Third-party taps are arbitrary code from GitHub, run with your user's permissions. Add ones you trust.")
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.tint(0.07),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(theme.tint(0.28), lineWidth: 0.5)
                )
        }
        .padding(EdgeInsets(top: 14, leading: 30, bottom: 16, trailing: 30))
    }

    private func metaRow(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.3))
            value()
        }
    }

    private var tap: TapRecord? {
        guard let tapName else { return nil }
        return taps.inventory.taps.first { $0.name == tapName }
    }

    private func filteredPackages(for tap: TapRecord) -> [TapPackage] {
        TapProjection.filter(
            TapProjection.packages(for: tap, installed: installed.inventory),
            query: query,
            kind: kind
        )
    }

    /// A grant lets Homebrew load and run this tap's code as the user, so it
    /// goes through the confirmation gate. A revocation only reduces authority,
    /// so it does not (TM13 :482-488) — the asymmetry is the requirement.
    private func grantTrust(_ tap: TapRecord) {
        guard let command = TapCommand.trust(tap.name) else { return }
        _ = operations.request(command)
    }

    private func revokeTrust(_ tap: TapRecord) {
        guard let command = TapCommand.untrust(tap.name) else { return }
        operations.submit(command)
    }

    private func untap(_ tap: TapRecord) {
        guard let command = TapCommand.untap(tap.name) else { return }
        operations.submit(command)
    }

    private func requestForceUntap(_ name: TapName) {
        guard let evidence = currentForceEvidence(name),
              let command = TapCommand.forceUntap(evidence: evidence)
        else { return }
        _ = operations.request(command)
    }
}

/// The tap-scoped trust badge both tap surfaces render.
///
/// It takes its text rather than composing one, because TM12 requires the list
/// row and the detail header to read exactly one projection; a badge that knew
/// the words would be a second place for them to disagree.
struct TapTrustBadge: View {
    let text: String
    /// Distinct per surface. The row and the header render the **same**
    /// projection, so a single identifier resolves to two elements the moment a
    /// badged tap is selected — and an assertion that a badge is absent from the
    /// header would then be answered by the row that is still on screen.
    let identifier: String

    var body: some View {
        // Deliberately not uppercased. TM12 :422 pins the badge copy exactly,
        // and `.textCase(.uppercase)` changes what the user reads even though
        // the projection handed over the pinned string unaltered. The copy
        // itself is deliberately not repeated here, in a comment or anywhere
        // else: this view may render the projection and may not restate it.
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.3)
            .foregroundStyle(Theme.dangerText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Theme.dangerTint(0.18),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .accessibilityIdentifier(identifier)
    }
}

/// The design's compact action chip: tinted fill, hairline stroke, 28pt tall.
/// A style rather than a custom label so every tap button keeps its static
/// string-literal form, which `TapShippingProofTests` enumerates.
struct TapActionButtonStyle: ButtonStyle {
    var fill: Color
    var text: Color
    var stroke: Color = .clear
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
