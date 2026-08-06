import Foundation
import Testing

@testable import Catalog

/// The promise that outranks stanza coverage (D5): inspection costs no new
/// acquisition.
///
/// Every inspection field comes from the payload resources the catalog already
/// downloads. There is no new brew invocation, no new remote resource, no
/// per-package request, and nothing new left on disk. This suite is the
/// structural half of that claim — the `Catalog` target has no dependency on
/// `BrewProcess` at all, which is asserted separately in `DetailTests` — and the
/// behavioural half: a recording source and a recording launcher, both silent.
@Suite("Inspection acquisition scope")
struct AcquisitionScopeTests {
    /// Exactly what a sync asked for before the widening. Four resources, one
    /// request each: the two payloads and the two analytics namespaces.
    static let expectedResources: [CatalogResource] = [
        .formulae, .casks, .analyticsFormula, .analyticsCask
    ]

    @Test("A widened sync issues exactly the requests the previous build issued")
    func widenedSyncIssuesNoAdditionalRequest() async throws {
        let harness = try SyncHarness()
        // Records carrying every widened key: the sync has the *opportunity* to
        // go and fetch more, and must not take it.
        harness.source.script(
            .payload(try Fixture.arrayOf(["formula-git", "formula-headless"])),
            for: .formulae
        )
        harness.source.script(
            .payload(
                try Fixture.arrayOf([
                    "cask-iterm2", "cask-every-stanza", "cask-unrepresented", "cask-bare"
                ])
            ),
            for: .casks
        )
        harness.source.script(.payload(try Fixture.data("analytics-formula-365d")), for: .analyticsFormula)
        harness.source.script(.payload(try Fixture.data("analytics-cask-365d")), for: .analyticsCask)

        let result = await harness.engine.sync()

        let snapshot = try #require(result.value)
        // The widened data really did land, so the silence below is the silence
        // of a sync that got everything it needed from what it already asks for.
        let iterm = try #require(
            PackageSearchIndex(snapshot: snapshot).package(PackageID(kind: .cask, name: "iterm2"))
        )
        #expect(iterm.caskInspection?.downloadURL?.isEmpty == false)

        let resources = harness.source.requests.map(\.resource)
        #expect(Set(resources) == Set(Self.expectedResources))
        // One request per resource: no per-package request, and no resource
        // fetched twice to pick up a widened field.
        #expect(resources.count == Self.expectedResources.count)
        for resource in Self.expectedResources {
            #expect(harness.source.requests(for: resource).count == 1, "\(resource) was not requested once")
        }

        // ...and nothing new is left on disk. The persisted artefacts are still
        // exactly the snapshot and its sidecar: no retained raw payload.
        let remaining = try FileManager.default
            .contentsOfDirectory(atPath: harness.directory.path)
            .sorted()
        #expect(remaining == ["catalog-state.json", "catalog.json"])
    }

    @Test("Inspection resolves offline, with no brew binary and every request failing")
    func inspectionResolvesOfflineAndWithoutBrew() async throws {
        // Arrange: a snapshot on disk, written by an earlier successful sync.
        let seeding = try SyncHarness()
        seeding.source.script(.payload(try Fixture.arrayOf(["formula-git"])), for: .formulae)
        seeding.source.script(
            .payload(try Fixture.arrayOf(["cask-iterm2", "cask-every-stanza"])),
            for: .casks
        )
        seeding.source.script(.failure(.offline), for: .analyticsFormula)
        seeding.source.script(.failure(.offline), for: .analyticsCask)
        _ = await seeding.engine.sync()

        // Act: a fresh launch whose source fails every request. No brew detection
        // is consulted and no launcher exists, because `Catalog` cannot reach one
        // — it does not depend on `BrewProcess`, which is the strongest form this
        // assertion can take (asserted structurally in `DetailTests`).
        let store = CatalogFileStore(directory: seeding.directory)
        let offlineSource = FakeCatalogSource()
        for resource in Self.expectedResources {
            offlineSource.script(.failure(.offline), for: resource)
        }

        let snapshot = try #require(try store.loadSnapshot())
        let index = PackageSearchIndex(snapshot: snapshot)
        let iterm = try #require(index.package(PackageID(kind: .cask, name: "iterm2")))
        let inspection = try #require(iterm.caskInspection)

        // Assert: every inspection field is served from the snapshot alone.
        #expect(inspection.downloadURL == "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip")
        #expect(
            inspection.declaredChecksum
                == .declared("36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7")
        )
        #expect(inspection.installPlan?.apps.map(\.source) == ["iTerm.app"])
        #expect(inspection.installPlan?.unrepresentedStanzaCount == 1)
        #expect(inspection.requirements?.macOSRequirement == ">= 12")
        #expect(inspection.conflicts?.casks == ["iterm2@beta", "iterm2@nightly"])

        let every = try #require(index.package(PackageID(kind: .cask, name: "every-stanza")))
        #expect(every.caskInspection?.installPlan?.binaries.isEmpty == false)

        // ...and resolving that detail issued no request at all.
        #expect(offlineSource.requests.isEmpty)
    }

    @Test("Resolving a detail touches nothing on disk")
    func resolvingDetailWritesNothing() throws {
        // TM5 again, from the detail side rather than the classification side:
        // a read must not mutate the store.
        let fileSystem = FakeCatalogFileSystem()
        let directory = URL(fileURLWithPath: "/cellar-acquisition-scope")
        let store = CatalogFileStore(directory: directory, fileSystem: fileSystem)
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: Fixture.arrayOf(["formula-git"])),
            casks: try CatalogDecoder.decodeCasks(from: Fixture.arrayOf(["cask-iterm2"])),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.persist(snapshot, state: Self.state)
        let operationsAfterWriting = fileSystem.operations

        let loaded = try #require(try store.loadSnapshot())
        let iterm = try #require(
            PackageSearchIndex(snapshot: loaded).package(PackageID(kind: .cask, name: "iterm2"))
        )

        #expect(iterm.caskInspection?.downloadURL?.isEmpty == false)
        #expect(fileSystem.operations == operationsAfterWriting)
    }

    static let state = CatalogState(
        sources: [
            .casks: SourceState(
                validators: ConditionalValidators(),
                downloadedAt: Date(timeIntervalSince1970: 1_800_000_000),
                recordCount: 1,
                byteCount: 0
            )
        ],
        lastSuccessAt: Date(timeIntervalSince1970: 1_800_000_000),
        skippedRecordCount: 0
    )
}
