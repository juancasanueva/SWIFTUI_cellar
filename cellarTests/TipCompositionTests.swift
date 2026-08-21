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
    private static func swiftSources() throws -> [AppSecuritySources.Source] {
        let root = AppSecuritySources.directory.deletingLastPathComponent()
        var sources: [AppSecuritySources.Source] = []
        for directory in ["cellar", "cellarTests"] {
            let url = root.appendingPathComponent(directory, isDirectory: true)
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                sources.append(
                    AppSecuritySources.Source(
                        name: "\(directory)/\(file.lastPathComponent)",
                        code: AppSecuritySources.stripComments(from: text)
                    )
                )
            }
        }
        return sources
    }

    @Test("No Swift source in the app or its tests carries a price literal")
    func noSwiftSourceInTheAppOrItsTestsCarriesAPriceLiteral() throws {
        let sources = try Self.swiftSources()
        #expect(sources.count > 20, "the sweep read almost nothing, so its silence means nothing")
        #expect(
            sources.contains { $0.name.hasSuffix("StoreKitTipSourceTests.swift") },
            "the tests are out of scope, and a price literal in a test is forbidden too"
        )

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
        let marker = "private var tipSignpostRow"
        guard let start = source.code.range(of: marker) else {
            Issue.record("AboutView carries no tip signpost row")
            return ""
        }
        let rest = source.code[start.upperBound...]
        guard let end = rest.range(of: "\n    private ") ?? rest.range(of: "\n    var ") else {
            return String(rest)
        }
        return String(rest[..<end.lowerBound])
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
