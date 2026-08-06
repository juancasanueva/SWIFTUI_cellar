import Foundation
import Testing

@testable import Catalog

/// The hand-picked list that ships inside the app (proposal D1,
/// package-discovery PD-R3 and PD-R4).
///
/// Two separate promises, and this suite keeps them separate because their
/// owners are different: a **malformed entry** is a bug in the file this
/// repository ships, and an **unresolvable token** is ordinary catalog drift
/// nobody did wrong. Conflating them into one number is a mistake slice 1
/// already paid for.
@Suite("Curated discovery list")
struct CuratedDiscoveryTests {
    // MARK: - Tolerant decoding (PD-R3 sc2)

    @Test("Unknown fields are discarded and every malformed entry is skipped and counted")
    func tolerantDecodeDiscardsUnknownKeysAndCountsSkips() async throws {
        // The fixture carries five distinct malformed shapes — no blurb, a blank
        // blurb, no token, no kind, an unknown kind — beside three well-formed
        // entries and several keys the decoder does not model.
        let list = try await CuratedDiscoveryList.decode(Fixture.discovery("curated-tolerant"))

        // One bad entry never costs the file: every well-formed entry survived.
        let tokens = list.categories.flatMap { $0.entries.map(\.token) }
        #expect(tokens == ["ripgrep", "iterm2", "jq"])
        #expect(list.categories.map(\.id) == ["tolerant-a", "tolerant-b"])

        // ...and each of the five was counted rather than silently dropped.
        #expect(list.skippedRecordCount == 5)

        // None of the malformed entries arrived under a substituted value.
        #expect(tokens.contains("noblurb") == false)
        #expect(tokens.contains("blankblurb") == false)
        #expect(tokens.contains("nokind") == false)
        #expect(tokens.contains("unknownkind") == false)

        // The unmodelled keys were discarded rather than failing the decode, and
        // the modelled ones decoded exactly as published.
        let ripgrep = try #require(list.categories.first?.entries.first)
        #expect(ripgrep.kind == .formula)
        #expect(ripgrep.token == "ripgrep")
        #expect(ripgrep.blurb == "Search a whole project in a blink.")

        let iterm = try #require(list.categories.first?.entries.last)
        #expect(iterm.kind == .cask)
        #expect(iterm.blurb == "A terminal you can actually configure.")
    }

    @Test("A blank blurb is skipped rather than filled in from somewhere else")
    func blankBlurbIsSkippedNotSubstituted() async throws {
        // The distinction that matters: a blurb says *why you might want this* in
        // Cellar's voice, so an entry without one is not renderable. Falling back
        // to the package's own `desc` would publish Homebrew's words as ours.
        let list = try await CuratedDiscoveryList.decode(Fixture.discovery("curated-tolerant"))

        #expect(list.categories.flatMap { $0.entries }.contains { $0.blurb.isEmpty } == false)
        #expect(list.categories.flatMap { $0.entries }.allSatisfy { $0.blurb.isEmpty == false })
    }

    // MARK: - Duplicates (PD-R3 sc3)

    @Test("A duplicate token resolves once, in the category that declared it first")
    func duplicateTokenResolvesOnceInTheFirstCategory() async throws {
        let list = try await CuratedDiscoveryList.decode(Fixture.discovery("curated-duplicate"))

        let placements = list.categories.flatMap { category in
            category.entries.map { (category: category.id, token: $0.token) }
        }
        let ripgrepPlacements = placements.filter { $0.token == "ripgrep" }

        #expect(ripgrepPlacements.count == 1)
        #expect(ripgrepPlacements.first?.category == "first")
        // The redundant declaration is counted, not silently dropped.
        #expect(list.skippedRecordCount == 1)
        // ...and the second category keeps the entry that was not a duplicate.
        #expect(list.categories.map(\.id) == ["first", "second"])
        #expect(list.categories.last?.entries.map(\.token) == ["iterm2"])
        // The surviving blurb is the first declaration's, not the second's.
        #expect(
            ripgrepPlacements.isEmpty == false,
            "no ripgrep entry survived, so the blurb assertion below proves nothing"
        )
        let ripgrep = try #require(
            list.categories.flatMap { $0.entries }.first { $0.token == "ripgrep" }
        )
        #expect(ripgrep.blurb == "Declared here first, so this is the one that survives.")
    }

    // MARK: - Declared order (PD-R3 sc4)

    @Test("Declared category and entry order survives decoding")
    func declaredOrderSurvivesDecoding() async throws {
        // Deliberately not alphabetical in either dimension: a decoder that
        // re-sorted would pass an alphabetical fixture and fail its users.
        let list = try await CuratedDiscoveryList.decode(Fixture.discovery("curated-unsorted"))

        #expect(list.categories.map(\.id) == ["zeta", "alpha", "mu"])
        #expect(list.categories.map(\.title) == ["Zeta", "Alpha", "Mu"])
        #expect(list.categories[0].entries.map(\.token) == ["wget", "jq", "curl"])
        #expect(list.categories[1].entries.map(\.token) == ["iterm2", "firefox"])
        #expect(list.categories[2].entries.map(\.token) == ["ripgrep", "fd"])
        #expect(list.skippedRecordCount == 0)
    }

    @Test("A category that cannot be placed counts the entries it declared")
    func unplaceableCategoryCountsItsEntries() async throws {
        // Two shapes the fixtures do not carry, because they are defects of the
        // *container* rather than of an entry: a category with no id, so its
        // entries have nowhere to go, and an array element that is not an
        // object at all.
        let data = Data(
            """
            {"categories": [
              {"title": "No id at all", "entries": [
                {"kind":"formula","token":"wget","blurb":"Nowhere to put this."},
                {"kind":"formula","token":"curl","blurb":"Nor this."}]},
              17,
              {"id":"good","title":"Good","entries":[
                {"kind":"formula","token":"jq","blurb":"This one has a home."}]}
            ]}
            """.utf8
        )

        let list = try await CuratedDiscoveryList.decode(data)

        // The readable category still arrives — a broken sibling never costs it.
        #expect(list.categories.map(\.id) == ["good"])
        #expect(list.categories.first?.entries.map(\.token) == ["jq"])
        // Two orphaned entries, plus the element that was not a category.
        #expect(list.skippedRecordCount == 3)
    }

    // MARK: - The shipped resource (PD-R3 sc1)

    @Test("The shipped curated list decodes through the accessor the app uses")
    func shippedListDecodesWithinItsDeclaredBounds() async throws {
        // Loaded through `shipped()` rather than by reading the file off disk:
        // this is the accessor the app itself calls, so a resource bundle that
        // never reached the product fails here rather than at launch.
        let list = try await CuratedDiscoveryList.shipped()

        // D1's shape, asserted rather than left as a comment in the JSON.
        #expect((3...5).contains(list.categories.count))
        let entries = list.categories.flatMap(\.entries)
        #expect((20...30).contains(entries.count))

        // The seed list must not ship already broken: every entry the file
        // declares is exposable, so a typo is a failing test and not a quietly
        // shorter list on a user's machine.
        #expect(list.skippedRecordCount == 0)

        // Every entry is a complete recommendation.
        #expect(entries.allSatisfy { $0.token.isEmpty == false })
        #expect(entries.allSatisfy { $0.blurb.isEmpty == false })
        // Both namespaces are represented, so the list is not accidentally
        // formula-only.
        #expect(entries.contains { $0.kind == .formula })
        #expect(entries.contains { $0.kind == .cask })
        // Categories are named, because a category is a heading a user reads.
        #expect(list.categories.allSatisfy { $0.title.isEmpty == false })
        #expect(list.categories.allSatisfy { $0.entries.isEmpty == false })
    }

    @Test("Every registered discovery fixture reached the test bundle")
    func everyDiscoveryFixtureIsInTheBundle() throws {
        for name in Fixture.discoveryFixtures {
            #expect(throws: Never.self) { _ = try Fixture.discovery(name) }
        }
        #expect(Fixture.discoveryFixtures.count == 8)
    }

    // MARK: - Resolution against the snapshot (PD-R4)

    @Test("A token the snapshot no longer holds is skipped, counted, and never a dead row")
    func removedTokenIsSkippedAndCounted() {
        let list = Self.list([
            ("staples", [(.formula, "wget", "Pull a file down over HTTP.")]),
            ("gonemissing", [(.formula, "gone", "A package that used to exist.")])
        ])

        let resolved = list.resolved(against: [Self.package("wget")])

        let tokens = resolved.categories.flatMap { $0.entries.map(\.package.name) }
        #expect(tokens == ["wget"])
        #expect(tokens.contains("gone") == false)
        #expect(resolved.unresolvedEntryCount == 1)
        // sc3: the category emptied by that skip disappears rather than being
        // exposed as an empty heading, and the other category is untouched.
        #expect(resolved.categories.map(\.id) == ["staples"])
    }

    @Test("A fully resolving list reports zero unresolved, not absent")
    func fullyResolvingListReportsZero() {
        let list = Self.list([
            ("staples", [
                (.formula, "wget", "Pull a file down over HTTP."),
                (.cask, "iterm2", "A terminal you can configure.")
            ])
        ])

        let resolved = list.resolved(against: [Self.package("wget"), Self.package("iterm2", .cask)])

        #expect(resolved.categories.flatMap { $0.entries.map(\.package.name) } == ["wget", "iterm2"])
        // Zero rather than absent: "everything resolved" is a fact worth
        // reporting, and an optional here would make it indistinguishable from
        // "nobody checked".
        #expect(resolved.unresolvedEntryCount == 0)
    }

    @Test("A category emptied by skips disappears while its siblings are unaffected")
    func categoryEmptiedBySkipsDisappears() {
        let list = Self.list([
            ("alive", [(.formula, "wget", "Pull a file down over HTTP.")]),
            ("allgone", [
                (.formula, "gone", "Not in the catalog."),
                (.formula, "alsogone", "Also not in the catalog.")
            ]),
            ("alsoalive", [(.cask, "iterm2", "A terminal you can configure.")])
        ])

        let resolved = list.resolved(against: [Self.package("wget"), Self.package("iterm2", .cask)])

        #expect(resolved.categories.map(\.id) == ["alive", "alsoalive"])
        #expect(resolved.categories.contains { $0.entries.isEmpty } == false)
        #expect(resolved.unresolvedEntryCount == 2)
    }

    @Test("Curated skips are their own count, distinct from the snapshot's")
    func curatedSkipsAreTheirOwnCount() {
        // Three genuinely different numbers, and the whole point of this test is
        // that none of them absorbs another:
        //   * the snapshot's `skippedRecordCount` — records Homebrew published
        //     that the catalog decoder could not read;
        //   * `unresolvedEntryCount` — valid curated entries with no catalog
        //     match, which is ordinary drift;
        //   * the curated `skippedRecordCount` — malformed entries in the file
        //     this repository ships, which is a shipping bug.
        let snapshot = CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 3,
            packages: [Self.package("wget")]
        )
        let list = CuratedDiscoveryList(
            categories: [
                CuratedCategory(
                    id: "mixed",
                    title: "Mixed",
                    entries: [
                        CuratedEntry(kind: .formula, token: "wget", blurb: "Still here."),
                        CuratedEntry(kind: .formula, token: "gone", blurb: "Not in the catalog."),
                        CuratedEntry(kind: .cask, token: "alsogone", blurb: "Also not in the catalog.")
                    ]
                )
            ],
            // Two entries the shipped file published malformed, counted at decode.
            skippedRecordCount: 4
        )

        let resolved = list.resolved(against: snapshot.packages)

        #expect(resolved.unresolvedEntryCount == 2)
        #expect(resolved.skippedRecordCount == 4)
        #expect(snapshot.skippedRecordCount == 3)
    }

    @Test("A resolved blurb is the resource's words, never the package's own description")
    func resolvedBlurbNeverFallsBackToThePackageDescription() throws {
        let package = CatalogPackage.stub(
            kind: .formula,
            name: "wget",
            desc: "Internet file retriever"
        )
        let list = Self.list([
            ("staples", [(.formula, "wget", "Pull a file down over HTTP without opening a browser.")])
        ])

        let resolved = list.resolved(against: [package])

        let entry = try #require(resolved.categories.first?.entries.first)
        #expect(entry.blurb == "Pull a file down over HTTP without opening a browser.")
        #expect(entry.blurb != package.desc)
        // The package still travels with the row, so a view can render the
        // catalog's own description *beside* the blurb — it just never becomes
        // the blurb.
        #expect(entry.package.desc == "Internet file retriever")
    }

    @Test("Resolving an empty list is empty rather than a failure")
    func resolvingAnEmptyListIsEmpty() {
        let resolved = CuratedDiscoveryList.empty.resolved(against: [Self.package("wget")])

        #expect(resolved.categories.isEmpty)
        #expect(resolved.unresolvedEntryCount == 0)
        #expect(resolved.skippedRecordCount == 0)
    }

    // MARK: - Helpers

    static func package(_ name: String, _ kind: PackageKind = .formula) -> CatalogPackage {
        CatalogPackage.stub(kind: kind, name: name)
    }

    /// A curated list from a compact literal, so each test reads as the shape it
    /// is asserting on rather than as three nested initialisers.
    static func list(
        _ categories: [(String, [(PackageKind, String, String)])]
    ) -> CuratedDiscoveryList {
        CuratedDiscoveryList(
            categories: categories.map { id, entries in
                CuratedCategory(
                    id: id,
                    title: id.capitalized,
                    entries: entries.map { CuratedEntry(kind: $0.0, token: $0.1, blurb: $0.2) }
                )
            },
            skippedRecordCount: 0
        )
    }
}
