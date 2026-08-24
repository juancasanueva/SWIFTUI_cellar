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

    // MARK: - package-trust PT3 :180-194 — attribution, and what it refuses

    /// **DD-5, R6.** Two conditions, both required. Prefix alone would attribute
    /// an entry for a package the tap does not publish; publication alone would
    /// attribute a bare `widget` to every tap that publishes a `widget`. And
    /// neither is a positional split, because a real `formulae` entry is
    /// URL-shaped and every positional split misreads it.
    @Test("Attribution requires both the prefix and the publication")
    func attributionRequiresBothThePrefixAndThePublication() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["acme/tools/desk"]
        )

        // Prefix only: this tap's prefix, a package it does not publish.
        let prefixOnly = TapProjection.grants(
            for: tap,
            in: .reported(TrustGrantLedger(formulae: ["acme/tools/ghost"]))
        )
        #expect(prefixOnly.marked.isEmpty)
        #expect(prefixOnly.countLine == nil)

        // Publication only: a bare token this tap really does publish.
        let bare = TapProjection.grants(
            for: tap,
            in: .reported(TrustGrantLedger(formulae: ["widget"]))
        )
        #expect(bare.marked.isEmpty)
        #expect(bare.countLine == nil)

        // Both: attributed.
        let both = TapProjection.grants(
            for: tap,
            in: .reported(TrustGrantLedger(formulae: ["acme/tools/widget"]))
        )
        #expect(both.marked == [PackageID(kind: .formula, name: "widget")])
        #expect(both.countLine == "1 trusted individually")

        // The URL-shaped entry: carried forward, never crashed, never split.
        let urlEntry = "https://github.com/cloudmanic/spice-edit/spice-edit"
        let splitCandidates = [
            TapRecord(name: "github.com/cloudmanic", repository: "cloudmanic",
                      formulaNames: ["spice-edit"]),
            TapRecord(name: "cloudmanic/spice-edit", repository: "spice-edit",
                      formulaNames: ["spice-edit"]),
            TapRecord(name: "https:/", repository: "github.com", formulaNames: ["spice-edit"])
        ]
        for candidate in splitCandidates {
            let presentation = TapProjection.grants(
                for: candidate,
                in: .reported(TrustGrantLedger(formulae: [urlEntry]))
            )
            #expect(
                presentation.marked.isEmpty,
                "\(candidate.name) was derived from the URL entry's components"
            )
            #expect(presentation.countLine == nil)
        }
        // …and it is surfaced rather than dropped.
        let accounting = TapProjection.accounting(
            of: TrustGrantLedger(formulae: [urlEntry]),
            taps: splitCandidates
        )
        #expect(accounting.unmatchedFormulae == [urlEntry])
        #expect(accounting.total == 1)
    }

    /// **PT3 :211-217, PD8 :65-71.** The bare-name hazard, pinned before the
    /// marker exists: a grant for `acme/tools/widget` lighting up every other
    /// `widget` on the machine is one `hasSuffix` away at all times.
    @Test("A same-named package under another tap is not claimed")
    func aSameNamedPackageUnderAnotherTapIsNotClaimed() {
        let report = TrustGrantState.reported(TrustGrantLedger(formulae: ["acme/tools/widget"]))
        let other = TapRecord(
            name: "other/tools",
            repository: "tools",
            formulaNames: ["other/tools/widget"]
        )
        let widget = PackageID(kind: .formula, name: "widget")

        #expect(TapProjection.grants(for: other, in: report).marked.isEmpty)
        #expect(TapProjection.grants(for: other, in: report).countLine == nil)
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "other/tools", in: report) == false)
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "homebrew/core", in: report) == false)
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "homebrew/cask", in: report) == false)

        // Positively anchored: the tap that really does publish it is marked, so
        // the four refusals above are not a rule that refuses everything.
        let acme = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"]
        )
        #expect(TapProjection.grants(for: acme, in: report).marked == [widget])
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "acme/tools", in: report))
    }

    // MARK: - PT5 :287-302 — one projection value, and its exact copy

    @Test("One projection carries the count and the marked set")
    func oneProjectionCarriesTheCountAndTheMarkedSet() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget", "acme/tools/helper"],
            caskTokens: ["acme/tools/desk"]
        )
        let two = TrustGrantState.reported(TrustGrantLedger(
            formulae: ["acme/tools/widget"],
            casks: ["acme/tools/desk"]
        ))

        // The row's value and the header's value are the same value: one call,
        // one result, and the type is `Equatable` so two calls cannot disagree.
        let row = TapProjection.grants(for: tap, in: two)
        let header = TapProjection.grants(for: tap, in: two)
        #expect(row == header)
        #expect(row.countLine == "2 trusted individually")
        #expect(row.marked == [
            PackageID(kind: .formula, name: "widget"),
            PackageID(kind: .cask, name: "desk")
        ])

        // Singular, exactly.
        let one = TapProjection.grants(
            for: tap,
            in: .reported(TrustGrantLedger(formulae: ["acme/tools/helper"]))
        )
        #expect(one.countLine == "1 trusted individually")
        #expect(one.marked == [PackageID(kind: .formula, name: "helper")])
    }

    /// **DD-7, D-c.** A package under a *trusted* tap is loadable with no
    /// individual entry at all, so "no entry" is not a fact about trust — and a
    /// zero beside an `Untrusted` badge would read as a verdict (TM11).
    @Test("Nothing is claimed for unreported or zero")
    func nothingIsClaimedForUnreportedOrZero() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"]
        )
        let empty = TrustGrantState.reported(TrustGrantLedger(
            formulae: [],
            casks: [],
            declaredNamespaces: ["formulae", "casks"]
        ))
        let noneForThisTap = TrustGrantState.reported(
            TrustGrantLedger(formulae: ["other/tools/widget"])
        )

        for state in [TrustGrantState.unreported, empty, noneForThisTap] {
            let presentation = TapProjection.grants(for: tap, in: state)
            #expect(presentation.countLine == nil, "\(state) claimed a count line")
            #expect(presentation.marked.isEmpty, "\(state) marked a package")
        }

        // No rendering anywhere states a zero, or anything negative about a
        // package. Enumerated over every string these states can produce.
        var rendered: [String] = []
        for state in [TrustGrantState.unreported, empty, noneForThisTap] {
            rendered.append(contentsOf: TapProjection.grants(for: tap, in: state).countLine.map { [$0] } ?? [])
            let section = TapProjection.unattributedSection(in: state, taps: [tap])
            rendered.append(contentsOf: [section.title] + [section.sentence].compactMap(\.self))
            rendered.append(contentsOf: section.groups.flatMap { [$0.title] + $0.entries })
        }
        #expect(rendered.isEmpty == false, "the copy enumeration collapsed")
        for line in rendered {
            #expect(line.contains("0 trusted individually") == false, "a zero count was rendered: \(line)")
            for negative in ["untrusted", "unsafe", "unverified", "unprotected", "not trusted"] {
                #expect(
                    line.localizedCaseInsensitiveContains(negative) == false,
                    "per-package copy says a package is \(negative): \(line)"
                )
            }
        }
    }

    @Test("The count is scoped to its own tap")
    func theCountIsScopedToItsOwnTap() {
        let acme = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"]
        )
        let other = TapRecord(
            name: "other/tools",
            repository: "tools",
            caskTokens: ["other/tools/desk"]
        )
        let report = TrustGrantState.reported(TrustGrantLedger(
            formulae: ["acme/tools/widget", "nobody/tools/lost"],
            casks: ["other/tools/desk"],
            taps: ["ghost/tools"]
        ))

        #expect(TapProjection.grants(for: acme, in: report).countLine == "1 trusted individually")
        #expect(TapProjection.grants(for: other, in: report).countLine == "1 trusted individually")
        #expect(TapProjection.grants(for: acme, in: report).marked
            == [PackageID(kind: .formula, name: "widget")])
        #expect(TapProjection.grants(for: other, in: report).marked
            == [PackageID(kind: .cask, name: "desk")])

        // Neither count includes the orphan tap grant or the unmatched package.
        let accounting = TapProjection.accounting(
            of: TrustGrantLedger(
                formulae: ["acme/tools/widget", "nobody/tools/lost"],
                casks: ["other/tools/desk"],
                taps: ["ghost/tools"]
            ),
            taps: [acme, other]
        )
        #expect(accounting.attributed == 2)
        #expect(accounting.orphanTapGrants == ["ghost/tools"])
        #expect(accounting.unmatchedFormulae == ["nobody/tools/lost"])
        #expect(accounting.total == 4)
    }

    // MARK: - PT6 :366-373, PT8 :443-449 — the exact copy, B1/B2/B3

    /// The design's drafted strings are superseded here. These are byte
    /// comparisons on purpose: the difference between "did not report" and
    /// "does not report", and between rendering nothing and rendering a
    /// sentence, is the whole of R4 in the copy.
    @Test("The section copy is exact and distinguishes the states")
    func theSectionCopyIsExactAndDistinguishesTheStates() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"]
        )
        let unreported = TapProjection.unattributedSection(in: .unreported, taps: [tap])
        let reportedEmpty = TapProjection.unattributedSection(
            in: .reported(TrustGrantLedger(declaredNamespaces: ["formulae", "casks"])),
            taps: [tap]
        )
        let orphaned = TapProjection.unattributedSection(
            in: .reported(TrustGrantLedger(taps: ["ghost/tools"])),
            taps: [tap]
        )
        let allAttributed = TapProjection.unattributedSection(
            in: .reported(TrustGrantLedger(formulae: ["acme/tools/widget"])),
            taps: [tap]
        )

        #expect(unreported.sentence == "This Homebrew does not report per-package trust.")
        #expect(reportedEmpty.sentence == "Homebrew records no packages trusted individually.")
        #expect(orphaned.sentence
            == "Homebrew still records these grants. Cellar shows them; it does not remove them.")
        #expect(allAttributed.sentence == nil, "a fully attributed report rendered a sentence")

        // Neither report-level state renders the other's copy, or a zero.
        #expect(unreported != reportedEmpty)
        #expect(unreported.sentence != reportedEmpty.sentence)
        #expect(reportedEmpty.groups.isEmpty)
        #expect(unreported.groups.isEmpty)
        for section in [unreported, reportedEmpty, orphaned, allAttributed] {
            let copy = [section.title] + [section.sentence].compactMap(\.self)
                + section.groups.map(\.title)
            for word in ["0 trusted", "expired", "stale", "inactive", "harmless"] {
                #expect(
                    copy.contains { $0.localizedCaseInsensitiveContains(word) } == false,
                    "the section describes a grant as \(word)"
                )
            }
        }
        // …and the orphan section names the tap it is about, and offers nothing.
        #expect(orphaned.groups.flatMap(\.entries) == ["ghost/tools"])
    }

    /// **TM12.6, DD-9.** The ledger's own `taps` namespace is decoded so nothing
    /// is dropped, and consumed for a tap's trust state by nothing at all — that
    /// state comes from `tap-info`, and a second source for it is precisely what
    /// TM12 forbids.
    @Test("The ledger's tap key never feeds a trust state")
    func theLedgersTapKeyNeverFeedsATrustState() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            trust: .untrusted
        )
        let namesThisTap = TrustGrantState.reported(TrustGrantLedger(taps: ["acme/tools"]))
        let states: [TrustGrantState] = [
            .unreported,
            .reported(TrustGrantLedger(declaredNamespaces: ["taps"])),
            namesThisTap,
            .reported(TrustGrantLedger(taps: ["acme/tools", "ghost/tools"]))
        ]

        let badge = TapProjection.trust(for: tap)
        #expect(badge.badge == "Untrusted")
        for state in states {
            #expect(TapProjection.trust(for: tap) == badge, "\(state) moved the badge")
            #expect(TapProjection.grants(for: tap, in: state).countLine == nil)
            #expect(TapProjection.grants(for: tap, in: state).marked.isEmpty)
        }

        // …and a `taps` entry contributes to no package category either: it is
        // an excluded tap grant, stated rather than dropped.
        let accounting = TapProjection.accounting(
            of: TrustGrantLedger(taps: ["acme/tools"]),
            taps: [tap]
        )
        #expect(accounting.excluded == 1)
        #expect(accounting.attributed == 0)
        #expect(accounting.unmatchedFormulae.isEmpty)
        #expect(accounting.unmatchedCasks.isEmpty)
        #expect(accounting.other.isEmpty)
        #expect(accounting.orphanTapGrants.isEmpty)
        #expect(accounting.total == 1)
    }

    // MARK: - PD8 :65-95 — the marker is exact, positive-only, and not a field

    @Test("A grant marks only the exact package it names")
    func aGrantMarksOnlyTheExactPackageItNames() {
        let report = TrustGrantState.reported(TrustGrantLedger(casks: ["acme/tools/widget"]))
        let widget = PackageID(kind: .cask, name: "widget")

        // Kind, name and tap of origin, all three.
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "acme/tools", in: report))
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "homebrew/cask", in: report) == false)
        #expect(TapProjection.grantsIndividually(widget, publishedBy: "other/tools", in: report) == false)
        #expect(TapProjection.grantsIndividually(
            PackageID(kind: .formula, name: "widget"),
            publishedBy: "acme/tools",
            in: report
        ) == false, "a cask grant marked a formula")
        #expect(TapProjection.grantsIndividually(
            PackageID(kind: .cask, name: "widget-pro"),
            publishedBy: "acme/tools",
            in: report
        ) == false)

        // Where identity cannot be established exactly, the answer is false —
        // and both no-grant states produce no marker of any kind.
        for state in [
            TrustGrantState.unreported,
            .reported(TrustGrantLedger(declaredNamespaces: ["casks"])),
            .reported(TrustGrantLedger(casks: ["other/tools/widget"]))
        ] {
            #expect(TapProjection.grantsIndividually(widget, publishedBy: "acme/tools", in: state) == false)
        }
        // The marker itself is one string, stated positively, and it is the only
        // one this surface has for a package.
        #expect(TapProjection.grantMarker == "Trusted individually")
    }

    /// **PD8 :81-87.** The marker is joined at presentation beside the tap fact.
    /// It is not, and must never become, a field of the catalog projection —
    /// that is what would quietly weaken PD7.
    @Test("The marker is not a projection field")
    func theMarkerIsNotAProjectionField() {
        let package = CatalogPackage(
            kind: .cask,
            name: "widget",
            displayName: "Widget",
            desc: nil,
            homepage: nil,
            license: nil,
            version: "1.0",
            tap: "acme/tools",
            dependencies: [],
            buildDependencies: [],
            dependents: [],
            caveats: nil,
            deprecated: false,
            deprecationReason: nil,
            deprecationDate: nil,
            disabled: false,
            disableReason: nil,
            disableDate: nil,
            autoUpdates: false,
            installCount365d: nil
        )
        // With a decoded report present, which is the condition under which a
        // field would be tempting.
        let report = TrustGrantState.reported(TrustGrantLedger(casks: ["acme/tools/widget"]))
        #expect(TapProjection.grantsIndividually(package.id, publishedBy: package.tap, in: report))

        let labels = Mirror(reflecting: package).children.compactMap(\.label)
        #expect(labels == [
            "kind", "name", "displayName", "desc", "homepage", "license", "version", "tap",
            "dependencies", "buildDependencies", "dependents", "caveats",
            "deprecated", "deprecationReason", "deprecationDate",
            "disabled", "disableReason", "disableDate",
            "autoUpdates", "installCount365d", "caskInspection", "formulaSources"
        ])
        #expect(labels.count == 22)
        for forbidden in ["trust", "grant", "verified", "signature", "notariz", "verdict"] {
            #expect(
                labels.contains { $0.localizedCaseInsensitiveContains(forbidden) } == false,
                "the catalog detail projection carries a \(forbidden) field"
            )
        }
    }

    // MARK: - PT8 :435-441 — an orphan grant is surfaced, not dropped

    @Test("A grant for an uninstalled tap is surfaced, not dropped")
    func aGrantForAnUninstalledTapIsSurfacedNotDropped() {
        let installed = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"]
        )
        let ledger = TrustGrantLedger(
            formulae: ["acme/tools/widget", "ghost/tools/lost"],
            taps: ["ghost/tools"]
        )
        let accounting = TapProjection.accounting(of: ledger, taps: [installed])

        #expect(accounting.orphanTapGrants == ["ghost/tools"])
        #expect(accounting.unmatchedFormulae == ["ghost/tools/lost"])
        #expect(accounting.attributed == 1)
        #expect(accounting.total == ledger.entryCount)
        // Counted in the unattributed totals, and in no tap's count.
        #expect(TapProjection.grants(for: installed, in: .reported(ledger)).countLine
            == "1 trusted individually")

        let section = TapProjection.unattributedSection(in: .reported(ledger), taps: [installed])
        #expect(section.groups.flatMap(\.entries).sorted() == ["ghost/tools", "ghost/tools/lost"])
        #expect(section.sentence
            == "Homebrew still records these grants. Cellar shows them; it does not remove them.")
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
