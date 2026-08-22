//
//  TipCompositionTests.swift
//  cellarTests
//

import Foundation
import Testing
import TipJar

@testable import cellar

/// Requirements 7 and 9 — the two structural halves of the tip jar.
///
/// Neither is a claim about what a view looks like; both are claims about what
/// the app target *contains*. "StoreKit appears in exactly one file" and "no
/// price literal exists anywhere" cannot be proved by importing the app and
/// asking it — they are absences across a whole directory, so they are read off
/// disk in the shipped `AppSecuritySources` idiom, comments stripped, anchored
/// to `#filePath` rather than to a working directory the runner does not
/// promise.
///
/// Every absence here is paired with either a positive anchor or a planted
/// violation. An absence asserted against a scanner that can no longer see
/// anything — a renamed directory, a mis-joined path, an over-eager comment
/// stripper — passes for free, and would keep passing for years.
@Suite("Tip composition")
struct TipCompositionTests {
    /// The one file allowed to import StoreKit.
    static let conformerName = "StoreKitTipSource.swift"

    /// Tokens no file but the conformer may name. `Product` and `Transaction`
    /// are matched on a word boundary, so `TipProduct` — the plain value that is
    /// allowed everywhere — does not trip them.
    static let storeKitTokens = [
        #"\bProduct\b"#,
        #"\bTransaction\b"#,
        #"\bAppStore\b"#,
        #"canMakePayments"#,
        #"currentEntitlements"#,
        #"appAccountToken"#
    ]

    private static func matches(_ pattern: String, in code: String) -> Bool {
        code.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - StoreKit is imported exactly once

    @Test("Exactly one file under the app target imports StoreKit, and it is the conformer")
    func exactlyOneFileUnderTheAppTargetImportsStoreKit() throws {
        let sources = try AppSecuritySources.load()
        #expect(sources.count > 3, "the app-source scanner read almost nothing")

        let importers = sources
            .filter { Self.matches(#"(?m)^import StoreKit$"#, in: $0.code) }
            .map(\.name)

        #expect(importers == [Self.conformerName], "StoreKit escaped its one seam")
    }

    @Test("No file but the conformer names a StoreKit type or a payments capability")
    func noFileButTheConformerNamesAStoreKitTypeOrAPaymentsCapability() throws {
        let sources = try AppSecuritySources.load()

        // The positive anchor: the conformer really does name them, so the
        // exclusion below is over a non-empty set rather than a description of
        // an empty one.
        let conformer = try #require(sources.first { $0.name == Self.conformerName })
        #expect(Self.matches(#"\bProduct\b"#, in: conformer.code))
        #expect(Self.matches(#"\bTransaction\b"#, in: conformer.code))

        for source in sources where source.name != Self.conformerName {
            for token in Self.storeKitTokens {
                #expect(
                    Self.matches(token, in: source.code) == false,
                    "\(source.name) names \(token) outside the one StoreKit seam"
                )
            }
        }
    }

    /// Requirement 4's structural half, and requirement 5's: a consumable is
    /// never entitled, never restored, and availability is never decided by the
    /// payments-capability flag or by a compile-time branch.
    @Test("Nothing is entitled, restorable, or decided at compile time")
    func nothingIsEntitledRestorableOrDecidedAtCompileTime() throws {
        let sources = try AppSecuritySources.load()

        for source in sources {
            for token in ["currentEntitlements", "AppStore.sync", "canMakePayments", "restorePurchases"] {
                #expect(source.code.contains(token) == false, "\(source.name) names \(token)")
            }
        }

        // The conformer is where such a call would most plausibly appear, so it
        // is checked for the branch forms too.
        let conformer = try #require(sources.first { $0.name == Self.conformerName })
        #expect(conformer.code.contains("#if") == false, "a compile-time branch decides the tip path")
        #expect(conformer.code.contains("#available") == false, "an availability check decides the tip path")
    }

    /// The control. Each assertion above is an absence; this plants the real
    /// thing and requires the scanner to find it, the way
    /// `SecurityCompositionTests` does for its own guard.
    @Test(
        "The scanner detects a planted StoreKit escape",
        arguments: [
            "import StoreKit",
            "let products = try await Product.products(for: ids)",
            "for await update in Transaction.updates {",
            "guard AppStore.canMakePayments else { return }",
            "for await entitlement in Transaction.currentEntitlements {",
            "try await product.purchase(options: [.appAccountToken(token)])"
        ]
    )
    func theScannerDetectsAPlantedStoreKitEscape(violation: String) {
        let tripped = Self.storeKitTokens.contains { Self.matches($0, in: violation) }
            || Self.matches(#"(?m)^import StoreKit$"#, in: violation)

        #expect(tripped, "the scanner missed a real violation: \(violation)")
    }

    /// And the other half of the control: the plain value the whole app is
    /// allowed to pass around must **not** trip the `Product` guard, or the
    /// sweep would be satisfied by a scanner that flags everything.
    @Test(
        "The scanner does not fire on the plain values the app may carry",
        arguments: [
            "let product: TipProduct = availability.product",
            "Text(product.displayPrice)",
            "@Environment(TipStore.self) private var tips",
            "await tips.tip()"
        ]
    )
    func theScannerDoesNotFireOnThePlainValuesTheAppMayCarry(ordinary: String) {
        for token in Self.storeKitTokens {
            #expect(
                Self.matches(token, in: ordinary) == false,
                "\(token) fired on an ordinary line: \(ordinary)"
            )
        }
    }

    // MARK: - Both verification branches reach the one finish()

    /// The structural half of requirement 3's unverified clause.
    ///
    /// `TipJarTests` executes the **decision** for both branches — an unverified
    /// transaction must still be finished — so what is left to prove here is the
    /// millimetre StoreKit owns: that the conformer's `switch` cannot leave
    /// without reaching the single `finish()` call the decision gates. That is a
    /// claim about the shape of one function, which is exactly what this file is
    /// for. It is asserted rather than described because `SKTestSession` cannot
    /// produce a transaction that fails verification, so no runtime test can
    /// walk that branch.
    /// One member's source, from its declaration to whichever member declaration
    /// comes next.
    ///
    /// The **earliest** boundary, not the first one that happens to match: an
    /// earlier version of this took `range(of: a) ?? range(of: b)`, which
    /// silently ran two members past the end and swept up a `return` belonging to
    /// something else. `??` picks the first non-nil marker, not the nearest one.
    static func member(named declaration: String, in code: String) -> String {
        guard let start = code.range(of: declaration) else { return "" }
        let rest = code[start.upperBound...]
        let boundaries = ["\n    private ", "\n    func ", "\n    var ", "\n    static "]
            .compactMap { rest.range(of: $0)?.lowerBound }
        guard let end = boundaries.min() else { return String(rest) }
        return String(rest[..<end])
    }

    private static func conformerFinishSource() throws -> String {
        let conformer = try #require(
            try AppSecuritySources.load().first { $0.name == Self.conformerName }
        )
        let source = member(named: "private static func finish(", in: conformer.code)
        if source.isEmpty { Issue.record("the conformer no longer has a finish(_:) function") }
        return source
    }

    @Test("Neither verification branch can leave the conformer without finishing")
    func neitherVerificationBranchCanLeaveTheConformerWithoutFinishing() throws {
        let finish = try Self.conformerFinishSource()
        #expect(finish.isEmpty == false, "the function was not found, so its shape proves nothing")

        // Both branches exist, and each one only classifies — it decides nothing
        // and returns nothing, so neither can short-circuit past the call below.
        #expect(finish.contains("case .verified("))
        #expect(finish.contains("case .unverified("))
        #expect(
            finish.contains("return") == finish.contains("return disposition.outcome"),
            "a branch returns early, so it can skip finishing"
        )
        #expect(
            finish.components(separatedBy: "return").count == 2,
            "there is more than one exit from finish(_:), so one of them may not finish"
        )

        // Exactly one `finish()` call, and it is gated only on the decision that
        // `TipJarTests` proves is `true` for a verified and an unverified
        // transaction alike.
        #expect(
            finish.components(separatedBy: "await transaction.finish()").count == 2,
            "the finishing call was duplicated or removed"
        )
        #expect(finish.contains("TipTransactionDisposition.forTransaction(isVerified: isVerified)"))
        #expect(finish.contains("if disposition.mustFinish { await transaction.finish() }"))
        #expect(
            finish.contains("if isVerified") == false,
            "verification decides the finish again, which is the whole failure mode"
        )
    }

    /// The control: the extractor really can tell a short-circuiting shape from
    /// a converging one, so the assertions above are not passing on an empty
    /// read.
    @Test("The finish-shape scanner rejects a branch that returns before finishing")
    func theFinishShapeScannerRejectsABranchThatReturnsBeforeFinishing() {
        let shortCircuit = """
                case .verified(let value):
                    await value.finish()
                    return .completed
                case .unverified:
                    return .unverified
            """

        #expect(shortCircuit.components(separatedBy: "return").count > 2)
        #expect(
            shortCircuit.contains("if disposition.mustFinish { await transaction.finish() }") == false
        )
    }

    // MARK: - Nothing is shown at launch

    /// Requirement 7.2 and the relaunch half of 7.3, which had no automated
    /// proof at all.
    ///
    /// "The surface is entered by the user, never pushed" is an absence across a
    /// known set of presentation modifiers, which is a scan rather than a UI
    /// test — and a UI test could not prove the *absence* of a prompt anyway
    /// without waiting for one that never comes.
    static let presentationModifiers = [
        ".sheet(", ".alert(", ".popover(", ".confirmationDialog(",
        ".fullScreenCover(", ".badge(", ".toast(", "NSAlert", "UNUserNotification"
    ]

    /// Every file this change introduced or touched on the tip path.
    static let tipSurfaceFiles = [
        "TipJarCard.swift", "StoreKitTipSource.swift", "TipThankYouPreference.swift",
        "AboutView.swift", "SettingsView.swift", "cellarApp.swift"
    ]

    @Test("No tip surface presents anything at launch or after any outcome")
    func noTipSurfacePresentsAnythingAtLaunchOrAfterAnyOutcome() throws {
        let sources = try AppSecuritySources.load()

        for name in Self.tipSurfaceFiles {
            let source = try #require(
                sources.first { $0.name == name },
                "\(name) is not in scope, so its silence means nothing"
            )
            for modifier in Self.presentationModifiers {
                #expect(
                    source.code.contains(modifier) == false,
                    "\(name) pushes \(modifier) at the user rather than waiting to be visited"
                )
            }
        }

        // The launch path specifically: the composition root starts the tip loop
        // and injects the environment, and does nothing else with it.
        let root = try #require(sources.first { $0.name == "cellarApp.swift" })
        #expect(
            Self.matches(#"\btips\.tip\(\)"#, in: root.code) == false,
            "launch initiates a purchase"
        )
    }

    /// The other half of 7.3: a dismissed tip produces no note, so nothing
    /// escalates on the next visit or the next launch.
    @Test("A cancelled outcome renders no note, and no outcome renders a follow-up prompt")
    func aCancelledOutcomeRendersNoNoteAndNoOutcomeRendersAFollowUpPrompt() throws {
        let card = try #require(
            try AppSecuritySources.load().first { $0.name == "TipJarCard.swift" }
        )

        // `.completed` and `.cancelled` share the one silent arm — the completed
        // case says thank you through the explanation copy, and the cancelled
        // case says nothing at all.
        let silentArm = try #require(card.code.range(of: "case .completed, .cancelled:"))
        let afterArm = card.code[silentArm.upperBound...].prefix(40)
        #expect(
            afterArm.contains("return nil"),
            "a dismissed tip now says something back, which is where a nag starts"
        )
        // The control: an arm that *does* speak exists, so the silence above is a
        // decision rather than a function that returns nothing for everything.
        #expect(card.code.contains(#"return "Waiting for approval."#))
        #expect(
            card.code.contains("case .pending:"),
            "the note stopped distinguishing outcomes at all"
        )
    }

    // MARK: - The About row appears only when there is something to point at

    /// Requirement 8.2's untested half.
    @Test("The About signpost is gated on the same availability value Settings reads")
    func theAboutSignpostIsGatedOnTheSameAvailabilityValueSettingsReads() throws {
        let sources = try AppSecuritySources.load()
        let about = try #require(sources.first { $0.name == "AboutView.swift" })

        #expect(
            about.code.contains("if tips.showsTipSurface {"),
            "the signpost is rendered unconditionally, so it points at nothing in a build that cannot transact"
        )
        // The gate has to wrap the row, not merely appear somewhere in the file.
        let gate = try #require(about.code.range(of: "if tips.showsTipSurface {"))
        let row = try #require(about.code.range(of: "tipSignpostRow\n"))
        #expect(gate.lowerBound < row.lowerBound)
        #expect(
            about.code.distance(from: gate.upperBound, to: row.lowerBound) < 120,
            "the gate and the row drifted apart, so the row may no longer be inside it"
        )

        // One availability answer, read from the injected store — not a second
        // evaluation that could disagree with the card's.
        #expect(about.code.contains("@Environment(TipStore.self)"))
        #expect(
            Self.matches(#"Product\.products"#, in: about.code) == false,
            "About asks the storefront a question of its own"
        )
    }

    // MARK: - The product id has one home

    /// Requirement 1.5 states a **structural** claim — "no second literal of that
    /// id exists in shipped source" — which the covering unit test could not make,
    /// because comparing a constant to its own literal proves only its value.
    @Test("The product id literal appears exactly once in shipped source")
    func theProductIDLiteralAppearsExactlyOnceInShippedSource() throws {
        let identifier = TipProductIDs.tip
        var occurrences: [String: Int] = [:]

        for source in try Self.shippedSources() {
            let count = source.code.components(separatedBy: identifier).count - 1
            if count > 0 { occurrences[source.name] = count }
        }

        #expect(
            occurrences == ["TipJar/TipProduct.swift": 1],
            "the product id is declared or repeated somewhere other than its one constant: \(occurrences)"
        )
    }

    // MARK: - No price literal exists anywhere

    /// A currency symbol followed by an amount. Deliberately requires the
    /// fraction digits: `$0` and `$1` are Swift's closure shorthand and appear on
    /// almost every page of this app, so a pattern without them would fire
    /// hundreds of times and be switched off within a week.
    static let currencyPattern = #"[$€£¥]\s?\d+[.,]\d{2}"#

    /// The sweep is scoped to `.swift` on purpose. `Tip.storekit` records a price
    /// tier because a StoreKit configuration has to; that is a fixture, not
    /// something this app renders, and a sweep that could not tell the two apart
    /// would have to be deleted rather than obeyed.
    /// Every Swift file this change is answerable for, read by area.
    ///
    /// `Packages/CellarCore/{Sources,Tests}/TipJar*` are in scope because
    /// requirement 7 says "the change's shipped sources **and its tests**", and
    /// the core target is both. Leaving the package out was a gap: a price
    /// literal in `TipProduct.swift` would have passed the sweep.
    private static func sources(in areas: [(label: String, path: String)]) throws
        -> [AppSecuritySources.Source] {
        let root = AppSecuritySources.directory.deletingLastPathComponent()
        var sources: [AppSecuritySources.Source] = []
        for area in areas {
            let url = root.appendingPathComponent(area.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("the sweep area \(area.path) does not exist, so it reads nothing")
                continue
            }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                sources.append(
                    AppSecuritySources.Source(
                        name: "\(area.label)/\(file.lastPathComponent)",
                        code: AppSecuritySources.stripComments(from: text)
                    )
                )
            }
        }
        return sources
    }

    private static func swiftSources() throws -> [AppSecuritySources.Source] {
        try sources(in: [
            ("cellar", "cellar"),
            ("cellarTests", "cellarTests"),
            ("TipJar", "Packages/CellarCore/Sources/TipJar"),
            ("TipJarTests", "Packages/CellarCore/Tests/TipJarTests")
        ])
    }

    /// What actually ships: the app target and the core target it links. Test
    /// sources are deliberately absent — a test may pin an id, and requirement
    /// 1.5's claim is about **shipped** source.
    private static func shippedSources() throws -> [AppSecuritySources.Source] {
        try sources(in: [
            ("cellar", "cellar"),
            ("TipJar", "Packages/CellarCore/Sources/TipJar")
        ])
    }

    @Test("No Swift source in the app, the core target, or their tests carries a price literal")
    func noSwiftSourceInTheAppOrItsTestsCarriesAPriceLiteral() throws {
        let sources = try Self.swiftSources()
        #expect(sources.count > 20, "the sweep read almost nothing, so its silence means nothing")
        #expect(
            sources.contains { $0.name.hasSuffix("StoreKitTipSourceTests.swift") },
            "the tests are out of scope, and a price literal in a test is forbidden too"
        )
        // The package halves, named individually: an area that silently read
        // nothing would leave the sweep passing over files it never opened.
        #expect(sources.contains { $0.name == "TipJar/TipProduct.swift" })
        #expect(sources.contains { $0.name == "TipJarTests/TipFakes.swift" })

        for source in sources {
            #expect(
                Self.matches(Self.currencyPattern, in: source.code) == false,
                "\(source.name) renders or asserts a price this app is not allowed to know"
            )
        }
    }

    /// The planted violations are **assembled from escapes** rather than
    /// written out. A guard that had to be switched off for the file that
    /// implements it would be a guard with a hole in it, and this way the price
    /// sweep above covers every `.swift` in the app and its tests with no
    /// exemption at all — including this one.
    @Test("The price scanner detects a planted literal and spares closure shorthand")
    func thePriceScannerDetectsAPlantedLiteralAndSparesClosureShorthand() {
        let dollar = "\u{24}"
        let euro = "\u{20AC}"
        let pound = "\u{A3}"
        let cases: [(line: String, isViolation: Bool)] = [
            ("Text(\"\(dollar)0.99\")", true),
            ("let price = \"\(euro)1,99\"", true),
            ("#expect(product.displayPrice == \"\(pound)0.99\")", true),
            ("Text(\"\(dollar) 4.50\")", true),
            ("products.map { $0.displayPrice }", false),
            ("VStack(spacing: 0.5) { }", false),
            ("Rectangle().frame(height: 0.5)", false),
            ("items.sorted { $0.name < $1.name }", false)
        ]

        for testCase in cases {
            #expect(
                Self.matches(Self.currencyPattern, in: testCase.line) == testCase.isViolation,
                "the price scanner answered wrongly for: \(testCase.line)"
            )
        }
    }

    // MARK: - No external payment link ships

    /// Guideline 3.1.1's exclusivity, as a test rather than as a note: a binary
    /// that transacts StoreKit may not also point the user somewhere else to pay.
    static let paymentDestinations = [
        "ko-fi", "kofi", "buymeacoffee", "paypal", "patreon",
        "github.com/sponsors", "stripe.com", "opencollective", "liberapay"
    ]

    /// This file is the one exemption, and only from this sweep.
    ///
    /// A scanner has to name what it looks for, so the table above would trip
    /// its own guard. The exemption is safe because it is exactly one file,
    /// named here rather than pattern-matched, and because the scanner is
    /// separately required to fire on a planted destination below — so an
    /// exemption that had quietly grown to cover the whole suite would fail.
    static let scannerFileName = "cellarTests/TipCompositionTests.swift"

    @Test("No external payment or donation destination appears in any source")
    func noExternalPaymentOrDonationDestinationAppearsInAnySource() throws {
        let sources = try Self.swiftSources()
        #expect(
            sources.contains { $0.name == Self.scannerFileName },
            "the exemption names a file the sweep does not even read"
        )

        for source in sources where source.name != Self.scannerFileName {
            let lowered = source.code.lowercased()
            for destination in Self.paymentDestinations {
                #expect(
                    lowered.contains(destination) == false,
                    "\(source.name) directs the user to pay outside the app, at \(destination)"
                )
            }
        }
    }

    /// The control for the exemption above.
    @Test("The destination scanner fires on a planted external payment link")
    func theDestinationScannerFiresOnAPlantedExternalPaymentLink() {
        let violations = [
            "Link(\"Support\", destination: URL(string: \"https://ko-fi.com/juan\")!)",
            "let sponsor = \"https://github.com/sponsors/juancasanueva\"",
            "Button(\"Donate\") { open(\"https://www.paypal.me/juan\") }"
        ]

        for violation in violations {
            let lowered = violation.lowercased()
            #expect(
                Self.paymentDestinations.contains { lowered.contains($0) },
                "the scanner missed a real external payment link: \(violation)"
            )
        }
    }

    // MARK: - The test store configuration never ships

    @Test("Tip.storekit lives with the tests and nowhere else")
    func tipStoreKitLivesWithTheTestsAndNowhereElse() throws {
        let root = AppSecuritySources.directory.deletingLastPathComponent()

        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("cellarTests/Tip.storekit").path
            ),
            "the configuration is missing, so the conformer's real-store proof cannot run"
        )

        // Nothing anywhere under the app target's own sources: the synchronized
        // root group treats a `.storekit` there as a resource of the shipping app
        // and copies it into `cellar.app/Contents/Resources` (probe U17).
        let enumerator = FileManager.default.enumerator(
            at: AppSecuritySources.directory,
            includingPropertiesForKeys: nil
        )
        var strays: [String] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "storekit" else { continue }
            strays.append(file.lastPathComponent)
        }
        #expect(strays.isEmpty, "a StoreKit configuration would ship inside the app: \(strays)")
    }

    @Test("The built app bundle carries no StoreKit configuration")
    func theBuiltAppBundleCarriesNoStoreKitConfiguration() throws {
        // The host of these tests is the app itself, so this reads the very
        // bundle a user would get.
        let bundle = Bundle.main
        #expect(
            bundle.bundleURL.lastPathComponent.hasSuffix(".app"),
            "the test host is not the app bundle, so this proves nothing"
        )
        #expect(
            bundle.url(forResource: "Tip", withExtension: "storekit") == nil,
            "the test configuration is a resource of the shipping app"
        )

        let resources = try #require(bundle.resourceURL)
        let contents = try FileManager.default.contentsOfDirectory(
            at: resources,
            includingPropertiesForKeys: nil
        )
        #expect(contents.isEmpty == false, "the bundle's resources could not be read")
        #expect(contents.contains { $0.pathExtension == "storekit" } == false)
    }

    // MARK: - Exactly one purchase call site exists

    /// Requirement 8. One place a purchase can be initiated is one place to
    /// prove correct — and the reason About is a signpost rather than a second
    /// button.
    @Test("Exactly one file invokes the purchasing seam")
    func exactlyOneFileInvokesThePurchasingSeam() throws {
        let sources = try AppSecuritySources.load()

        let callers = sources
            .filter { Self.matches(#"\.tip\(\)"#, in: $0.code) }
            .map(\.name)

        #expect(callers == ["TipJarCard.swift"], "the tip is purchasable from more than one place")
    }

    @Test("The composition root wires the tip store into both scenes and one loop slot")
    func theCompositionRootWiresTheTipStoreIntoBothScenesAndOneLoopSlot() throws {
        let sources = try AppSecuritySources.load()
        let root = try #require(sources.first { $0.name == "cellarApp.swift" })

        #expect(root.code.contains("StoreKitTipSource("), "the real conformer is never constructed")
        #expect(root.code.contains("AppTestTipSource("), "a UI-test launch would reach StoreKit")
        #expect(root.code.contains("TipThankYouPreference("))
        // Both scenes, so the two surfaces read one availability answer.
        #expect(
            root.code.components(separatedBy: ".environment(tips)").count == 3,
            "the tip store reaches one scene only, so About and Settings could disagree"
        )
        #expect(
            root.code.contains(#"loops.start("tips")"#),
            "the observation is not owned by the idempotent loop, so a second window doubles it"
        )
    }

    // MARK: - The About row is a signpost, and carries no action

    /// The row is extracted and read on its own. Asserting over the whole file
    /// would prove nothing: `AboutCommands` legitimately owns a `Button` and an
    /// `openWindow`, and the two existing link rows legitimately own a `Link`.
    /// What must carry no action is this row.
    private static func aboutSignpostSource() throws -> String {
        let source = try #require(
            try AppSecuritySources.load().first { $0.name == "AboutView.swift" }
        )
        let row = member(named: "private var tipSignpostRow", in: source.code)
        if row.isEmpty { Issue.record("AboutView carries no tip signpost row") }
        return row
    }

    @Test("The About signpost carries no action of any kind")
    func theAboutSignpostCarriesNoActionOfAnyKind() throws {
        let row = try Self.aboutSignpostSource()

        #expect(row.isEmpty == false, "the row was not found, so its silence means nothing")
        // The positive anchor: it really does name Settings as the location, so
        // the absences below are over a row that exists and says something.
        #expect(row.contains("Settings"), "the signpost does not name where tipping lives")

        for action in ["Link(", "Button(", "onTapGesture", "openWindow", "NavigationLink", "AppSection"] {
            #expect(row.contains(action) == false, "the About signpost carries an action: \(action)")
        }
    }

    @Test("The About surface never purchases and never selects a section")
    func theAboutSurfaceNeverPurchasesAndNeverSelectsASection() throws {
        let sources = try AppSecuritySources.load()
        let about = try #require(sources.first { $0.name == "AboutView.swift" })

        #expect(Self.matches(#"\.tip\(\)"#, in: about.code) == false, "About purchases the tip")
        #expect(about.code.contains("AppSection") == false, "About navigates to a section")
        #expect(about.code.contains("NavigationLink") == false)
    }

    /// Requirement 8's last scenario, structurally: the existing free-app card's
    /// copy is untouched and the tip card is an addition beside it.
    @Test("The free-app card's copy is unchanged and the tip card sits above it")
    func theFreeAppCardsCopyIsUnchangedAndTheTipCardSitsAboveIt() throws {
        let sources = try AppSecuritySources.load()
        let settings = try #require(sources.first { $0.name == "SettingsView.swift" })

        #expect(settings.code.contains(#"Text("Cellar is free, and stays free")"#))
        #expect(settings.code.contains(#"Text("No accounts, no telemetry, no paid tier.")"#))

        let card = try #require(settings.code.range(of: "TipJarCard()"))
        let free = try #require(settings.code.range(of: "freeCard"))
        #expect(card.lowerBound < free.lowerBound, "the tip card was placed below the free card")
    }

    // MARK: - The tip target depends on nothing

    @Test("The TipJar target declares an empty dependency list and imports no StoreKit")
    func theTipJarTargetDeclaresAnEmptyDependencyListAndImportsNoStoreKit() throws {
        let root = AppSecuritySources.directory.deletingLastPathComponent()
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Packages/CellarCore/Package.swift"),
            encoding: .utf8
        )
        let stripped = AppSecuritySources.stripComments(from: manifest)

        #expect(
            Self.matches(#"\.target\(\s*name: "TipJar",\s*dependencies: \[\],"#, in: stripped),
            "the tip jar gained a dependency, so it can now reach something it must not"
        )
        // The control: a sibling target that really does have dependencies must
        // not satisfy the same shape, or the pattern would be matching nothing.
        #expect(
            Self.matches(#"\.target\(\s*name: "Persistence",\s*dependencies: \[\],"#, in: stripped) == false,
            "the manifest scanner cannot tell an empty dependency list from a full one"
        )

        let tipSources = root.appendingPathComponent("Packages/CellarCore/Sources/TipJar")
        let enumerator = FileManager.default.enumerator(at: tipSources, includingPropertiesForKeys: nil)
        var read = 0
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let code = AppSecuritySources.stripComments(
                from: try String(contentsOf: file, encoding: .utf8)
            )
            read += 1
            #expect(
                Self.matches(#"(?m)^import StoreKit$"#, in: code) == false,
                "\(file.lastPathComponent) imports StoreKit into the core package"
            )
            for token in [#"\bProduct\b"#, #"\bTransaction\b"#, #"\bAppStore\b"#] {
                #expect(
                    Self.matches(token, in: code) == false,
                    "\(file.lastPathComponent) names \(token), so a StoreKit type crossed into CellarCore"
                )
            }
        }
        #expect(read >= 4, "the TipJar sources were not read, so their silence means nothing")
    }
}
