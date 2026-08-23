import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@Suite("Tap projection")
struct TapProjectionTests {
    @Test("Official sources appear once, are explanatory, and never mutate")
    func officialSourcesAreExplanatoryOnly() {
        let projection = TapProjection(inventory: TapInventory(taps: [
            TapRecord(name: "homebrew/core", repository: "core"),
            TapRecord(name: "homebrew/cask", repository: "cask")
        ]))

        #expect(projection.officialSources.map(\.title) == ["Homebrew Core", "Homebrew Cask"])
        #expect(projection.officialSources.allSatisfy {
            $0.explanation == "API-backed; no local tap required"
        })
        #expect(projection.officialSources.allSatisfy { $0.isMutable == false })
        #expect(projection.thirdPartyTaps.isEmpty)
        #expect(projection.canAddTap)
    }

    @Test("The package summary pluralizes, omits zero components, and names emptiness")
    func packageSummaryReadsLikeTheDesign() {
        #expect(summary(formulae: 5, casks: 1) == "5 formulae · 1 cask")
        #expect(summary(formulae: 1, casks: 2) == "1 formula · 2 casks")
        #expect(summary(formulae: 4, casks: 0) == "4 formulae")
        #expect(summary(formulae: 0, casks: 1) == "1 cask")
        #expect(summary(formulae: 0, casks: 0) == "No packages")
    }

    private func summary(formulae: Int, casks: Int) -> String {
        TapProjection.packageSummary(
            for: TapRecord(
                name: "acme/tools",
                repository: "tools",
                formulaNames: (0..<formulae).map { "f\($0)" },
                caskTokens: (0..<casks).map { "c\($0)" }
            )
        )
    }

    @Test("Only the selected tap prefix is removed and equal tokens keep kind identity")
    func packageIdentityAndDisplayAreKindAware() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget", "other/tap/widget"],
            caskTokens: ["widget"]
        )

        let packages = TapProjection.packages(for: tap, installed: .empty)

        #expect(packages.map(\.displayName) == ["widget", "other/tap/widget", "widget"])
        #expect(packages.map(\.id.kind) == [.formula, .formula, .cask])
        #expect(Set(packages.map(\.id)).count == 3)
    }

    @Test("Exact installed tap and package kind alone enable Installed handoff")
    func exactInstalledCrossReferenceControlsHandoff() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["widget"]
        )
        let installed = InstalledInventory(packages: [
            installedPackage(kind: .formula, name: "widget", tap: "acme/tools"),
            installedPackage(kind: .cask, name: "widget", tap: "other/tools")
        ])

        let packages = TapProjection.packages(for: tap, installed: installed)

        #expect(packages[0].installedHandoff == PackageID(kind: .formula, name: "widget"))
        #expect(packages[1].installedHandoff == nil)
        #expect(packages[1].statusExplanation == "Not installed.")
    }

    /// `brew tap-info --json` publishes cask tokens fully qualified —
    /// `acme/tools/widget` — exactly as it publishes formula names, while the
    /// installed snapshot keys the same cask by the token brew installs by,
    /// `widget`. The selected-tap prefix must be removed for casks by the same
    /// rule as for formulae, or an installed third-party cask can never match.
    @Test("A fully qualified cask token matches the installed cask by its bare token")
    func qualifiedCaskTokenMatchesTheInstalledCask() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: [],
            caskTokens: ["acme/tools/widget", "other/tap/gadget"]
        )
        let installed = InstalledInventory(packages: [
            installedPackage(kind: .cask, name: "widget", tap: "acme/tools")
        ])

        let packages = TapProjection.packages(for: tap, installed: installed)

        #expect(packages.map(\.displayName) == ["widget", "other/tap/gadget"])
        #expect(packages.map(\.publishedName) == ["acme/tools/widget", "other/tap/gadget"])
        #expect(packages[0].id == PackageID(kind: .cask, name: "widget"))
        #expect(packages[0].installedHandoff == PackageID(kind: .cask, name: "widget"))
        #expect(packages[0].statusExplanation == nil)
        #expect(packages[1].installedHandoff == nil)
    }

    @Test("Name and kind filters return only matching visible rows from a large inventory")
    func largeInventoryFiltersLazily() {
        let formulae = (0..<2_000).map { "acme/tools/formula-\($0)" }
        let casks = (0..<2_000).map { "cask-\($0)" }
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: formulae,
            caskTokens: casks
        )
        let all = TapProjection.packages(for: tap, installed: .empty)

        let visible = TapProjection.filter(all, query: "cask-199", kind: .cask)

        #expect(visible.map(\.displayName) == [
            "cask-199", "cask-1990", "cask-1991", "cask-1992", "cask-1993",
            "cask-1994", "cask-1995", "cask-1996", "cask-1997", "cask-1998", "cask-1999"
        ])
        #expect(visible.allSatisfy { $0.id.kind == .cask })
    }

    @Test("Brew absence, empty success, and failure remain distinct states")
    func presentationStatesRemainDistinct() {
        let absence = InstalledAbsence.notInstalled(.standard)
        #expect(TapProjection.state(loadState: .brewAbsent(absence), inventory: .empty) == .unavailable(absence))
        #expect(TapProjection.state(loadState: .loaded, inventory: .empty) == .content(isThirdPartyEmpty: true))
        #expect(
            TapProjection.state(loadState: .failed(.malformedJSON), inventory: .empty)
                == .error(.malformedJSON, hasLastGood: false)
        )
        let lastGood = TapInventory(taps: [TapRecord(name: "acme/tools", repository: "tools")])
        #expect(
            TapProjection.state(loadState: .failed(.cancelled), inventory: lastGood)
                == .error(.cancelled, hasLastGood: true)
        )
    }

    // MARK: - TM12 — the trust presentation

    /// One projection supplies the badge and both controls, so the three facts
    /// cannot disagree. `unreported` is the Homebrew-with-no-trust-concept case:
    /// it claims nothing and offers nothing, because a control that cannot
    /// succeed is worse than no control.
    @Test("The badge and controls follow the reported state, and an unreported tap offers neither")
    func unreportedTrustShowsNoBadgeAndNoControl() {
        let untrusted = TapProjection.trust(for: tapRecord(trust: .untrusted))
        #expect(untrusted.badge == "Untrusted")
        #expect(untrusted.canGrant)
        #expect(untrusted.canRevoke == false)

        let trusted = TapProjection.trust(for: tapRecord(trust: .trusted))
        #expect(trusted.badge == nil)
        #expect(trusted.canGrant == false)
        #expect(trusted.canRevoke)

        let unreported = TapProjection.trust(for: tapRecord(trust: .unreported))
        #expect(unreported.badge == nil)
        #expect(unreported.canGrant == false)
        #expect(unreported.canRevoke == false)
    }

    /// R7 — a package individually granted under an untrusted tap is loadable,
    /// so any string claiming *the package* is untrusted would be a false
    /// statement about this Mac. Every string this surface presents is about
    /// the tap (TM12 :467-473).
    @Test("Every trust string is scoped to the tap and none claims a package is untrusted")
    func everyTrustStringIsScopedToTheTap() {
        let strings = [TapTrustState.trusted, .untrusted, .unreported]
            .compactMap { TapProjection.trust(for: tapRecord(trust: $0)).badge }

        // Positively anchored: the enumeration is non-empty and is exactly the
        // copy this surface presents, so the prohibition below is not vacuous.
        #expect(strings == ["Untrusted"])
        for string in strings {
            for packageWord in ["package", "formula", "cask", "app "] {
                #expect(
                    string.localizedCaseInsensitiveContains(packageWord) == false,
                    "trust copy speaks about a package rather than the tap: \(string)"
                )
            }
        }
    }

    // MARK: - TM5 — the three installed states

    /// TM5 :113-120. Homebrew withholds the `tap` of a package published by a
    /// tap it will not load, so the exact-tap cross-reference finds nothing and
    /// the shipped projection was *required* to say "Not installed." — a false
    /// statement about this Mac. The middle state is the fix, and it is a third
    /// value rather than a second boolean because the package **is** installed.
    @Test("A withheld tap under an untrusted tap reads as installed, not as absent")
    func aWithheldTapIsInstalledNotMissing() throws {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/helper"],
            caskTokens: ["acme/tools/widget", "acme/tools/gadget"],
            trust: .untrusted
        )
        let installed = InstalledInventory(packages: [
            installedPackage(kind: .cask, name: "widget", tap: nil),
            installedPackage(kind: .formula, name: "helper", tap: "acme/tools")
        ])

        let packages = TapProjection.packages(for: tap, installed: installed)
        let widget = try #require(packages.first { $0.id == PackageID(kind: .cask, name: "widget") })
        let helper = try #require(packages.first { $0.id == PackageID(kind: .formula, name: "helper") })
        let gadget = try #require(packages.first { $0.id == PackageID(kind: .cask, name: "gadget") })

        // The middle state: installed, and brew is withholding which tap.
        #expect(widget.state == .installedTapWithheld(PackageID(kind: .cask, name: "widget")))
        #expect(widget.isInstalled)
        #expect(
            widget.statusExplanation
                == "Installed. Homebrew withholds its tap while this tap is untrusted."
        )
        // TM5 :62-63 — the handoff selects by exact `PackageID`, and that
        // identity is exact whatever brew withholds.
        #expect(widget.installedHandoff == PackageID(kind: .cask, name: "widget"))

        // The two states that already existed are unchanged.
        #expect(helper.state == .installed(PackageID(kind: .formula, name: "helper")))
        #expect(helper.statusExplanation == nil)
        #expect(helper.installedHandoff == PackageID(kind: .formula, name: "helper"))
        #expect(gadget.state == .notInstalled)
        #expect(gadget.isInstalled == false)
        #expect(gadget.statusExplanation == "Not installed.")
        #expect(gadget.installedHandoff == nil)
    }

    /// TM5 :122-128. The publication clause runs in both directions: a record
    /// with no tap that this tap does not publish is not this tap's package, and
    /// claiming it would be the same false statement pointed the other way.
    @Test("A withheld tap is not claimed by a tap that does not publish it")
    func aWithheldTapIsNotClaimedByATapThatDoesNotPublishIt() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            caskTokens: ["acme/tools/widget"],
            trust: .untrusted
        )
        let installed = InstalledInventory(packages: [
            installedPackage(kind: .cask, name: "stranger", tap: nil)
        ])

        let packages = TapProjection.packages(for: tap, installed: installed)

        // Positively anchored: the tap really does project its own package.
        #expect(packages.map(\.displayName) == ["widget"])
        #expect(packages.contains { $0.displayName == "stranger" } == false)
        #expect(packages.contains { $0.state == .installedTapWithheld(PackageID(kind: .cask, name: "stranger")) } == false)
        // And its own published package, with nothing installed under it, is
        // plainly not installed rather than withheld.
        #expect(packages[0].state == .notInstalled)
    }

    /// TM5 :130-137. Only an `untrusted` tap has anything withheld. Under a
    /// trusted tap brew reports the tap, and under an unreported one there is no
    /// trust concept to withhold for — so in both cases an absent tap is simply
    /// a package that did not come from here.
    @Test(
        "A withheld tap under a trusted or unreported tap is still not installed",
        arguments: [TapTrustState.trusted, .unreported]
    )
    func aWithheldTapUnderATrustedOrUnreportedTapIsStillNotInstalled(
        trust: TapTrustState
    ) throws {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            caskTokens: ["acme/tools/widget"],
            trust: trust
        )
        let installed = InstalledInventory(packages: [
            installedPackage(kind: .cask, name: "widget", tap: nil)
        ])

        let widget = try #require(TapProjection.packages(for: tap, installed: installed).first)

        #expect(widget.state == .notInstalled)
        #expect(widget.statusExplanation == "Not installed.")
        #expect(widget.installedHandoff == nil)
        #expect(
            widget.statusExplanation?.contains("withholds") == false,
            "the withheld copy escaped to a tap with nothing withheld"
        )
    }

    // MARK: - PM10 :348-357 — the recovery, from Cellar's own snapshot

    /// **DD-7.** The refusal carries nothing, so the tap the recovery offers to
    /// trust comes from the snapshot Cellar already holds — matched against a
    /// `PackageID` **Cellar itself typed**, never a token read out of brew's
    /// message.
    ///
    /// Exactly one candidate, or nothing. With two untrusted publishers of the
    /// same `(kind, name)` Cellar genuinely does not know which tap brew meant,
    /// and guessing would grant the wrong capability — so the typed message's
    /// own sentence is the path and no button is shown (R16).
    @Test("The recovery picks only a unique publisher from Cellar's own snapshot")
    func theRecoveryPicksOnlyAUniquePublisherFromCellarsOwnSnapshot() throws {
        let widget = PackageID(kind: .cask, name: "widget")
        let untrusted = TapRecord(
            name: "acme/tools",
            repository: "tools",
            caskTokens: ["acme/tools/widget"],
            trust: .untrusted
        )

        // One untrusted publisher — the only case that offers a grant.
        let single = TapInventory(taps: [untrusted])
        #expect(
            UntrustedTapRecovery.trustableTap(forRefused: widget, in: single)
                == TapName("acme/tools")
        )

        // Two untrusted publishers of the same identity — nothing is offered.
        let rival = TapRecord(
            name: "other/tools",
            repository: "tools",
            caskTokens: ["other/tools/widget"],
            trust: .untrusted
        )
        #expect(
            UntrustedTapRecovery.trustableTap(
                forRefused: widget,
                in: TapInventory(taps: [untrusted, rival])
            ) == nil
        )

        // A trusted or unreported publisher is not a candidate: trusting it
        // again would answer a refusal trust did not cause.
        for trust in [TapTrustState.trusted, .unreported] {
            let record = TapRecord(
                name: "acme/tools",
                repository: "tools",
                caskTokens: ["acme/tools/widget"],
                trust: trust
            )
            #expect(
                UntrustedTapRecovery.trustableTap(
                    forRefused: widget,
                    in: TapInventory(taps: [record])
                ) == nil
            )
        }

        // An official tap never reaches this surface at all (TM4).
        let official = TapRecord(
            name: "homebrew/cask",
            repository: "homebrew-cask",
            caskTokens: ["widget"],
            trust: .untrusted
        )
        #expect(
            UntrustedTapRecovery.trustableTap(
                forRefused: widget,
                in: TapInventory(taps: [official])
            ) == nil
        )

        // A tap that does not publish this exact `(kind, name)` is not a
        // candidate — kind included, which is why a same-named formula does not
        // answer for a cask.
        let formula = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            trust: .untrusted
        )
        #expect(
            UntrustedTapRecovery.trustableTap(
                forRefused: widget,
                in: TapInventory(taps: [formula])
            ) == nil
        )
        #expect(
            UntrustedTapRecovery.trustableTap(
                forRefused: PackageID(kind: .formula, name: "widget"),
                in: TapInventory(taps: [formula])
            ) == TapName("acme/tools")
        )

        // And a command with no package identity — `upgradeAll`, every tap
        // command — offers nothing.
        #expect(UntrustedTapRecovery.trustableTap(forRefused: nil, in: single) == nil)
    }

    /// The publication rule the recovery rests on, made callable (TM5 :122-128).
    @Test("A tap publishes only the exact kind and bare token it names")
    func publicationIsExactInKindAndToken() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/helper", "other/tap/widget"],
            caskTokens: ["acme/tools/widget"]
        )

        #expect(TapProjection.publishes(PackageID(kind: .formula, name: "helper"), in: tap))
        #expect(TapProjection.publishes(PackageID(kind: .cask, name: "widget"), in: tap))
        // Kind is part of identity.
        #expect(TapProjection.publishes(PackageID(kind: .cask, name: "helper"), in: tap) == false)
        #expect(TapProjection.publishes(PackageID(kind: .formula, name: "widget"), in: tap) == false)
        // Only the selected tap's own prefix is removed, so a foreign qualified
        // name is not claimed by its last component.
        #expect(TapProjection.publishes(PackageID(kind: .formula, name: "other/tap/widget"), in: tap))
        #expect(TapProjection.publishes(PackageID(kind: .formula, name: "stranger"), in: tap) == false)
    }

    private func tapRecord(trust: TapTrustState) -> TapRecord {
        TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["acme/tools/desk"],
            trust: trust
        )
    }

    private func installedPackage(kind: PackageKind, name: String, tap: String?) -> InstalledPackage {
        let keg = InstalledKeg(
            version: "1.0",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            installedOnRequest: true
        )
        return InstalledPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: tap,
            catalogVersion: "1.0",
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: false,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: kind == .cask ? false : nil
        )
    }
}
