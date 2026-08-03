import Foundation
import Observation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The confirmation gate's one writable position, closed (design D6 — register
/// item VS2).
///
/// `pendingConfirmation` was widened from `private(set)` to `internal(set)` when
/// the confirmation surface moved one file over. That is a real loosening: the
/// property is `public`, so `internal(set)` means *anything in the module* can
/// answer a confirmation on the user's behalf, and the compiler stopped being
/// the thing that prevented it.
///
/// The restoration goes further than VS2 asked. A nested `@Observable` box holds
/// the value and `pendingConfirmation` becomes a **computed getter with no
/// setter at all** — which is strictly stronger than `private(set)`, because
/// there is no setter to widen again.
@MainActor
@Suite("Confirmation box", .timeLimit(.minutes(1)))
struct ConfirmationBoxTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")

    // MARK: - The structural claim (VS2)

    /// **Anchored positively first** (the M3-0 task 8.1 lesson): a scan whose
    /// forbidden strings are all absent because it read the wrong file, or an
    /// empty one, passes while proving nothing. So the sources are asserted to
    /// contain the declaration under test *before* anything is asserted absent.
    @Test("The pending confirmation has no setter at all")
    func pendingConfirmationHasNoSetterAtAll() throws {
        let center = try Self.source(of: "OperationCenter.swift")
        let bulk = try Self.source(of: "OperationCenterBulk.swift")

        // Anchors: the property exists, it is public, and it is computed over
        // the box rather than stored.
        #expect(center.contains("public var pendingConfirmation"), "the property is not declared here")
        #expect(center.contains("ConfirmationBox"), "the centre does not hold a box")
        #expect(bulk.contains("class ConfirmationBox"), "the box is not declared where expected")

        // The claim: no access-level setter of any width survives on it.
        for widening in [
            "internal(set) var pendingConfirmation",
            "public(set) var pendingConfirmation",
            "private(set) var pendingConfirmation",
            "package(set) var pendingConfirmation"
        ] {
            #expect(
                center.contains(widening) == false,
                "\(widening) — the property regained a setter"
            )
        }

        // And nothing anywhere in the module assigns to it, which is what
        // "computed getter" means in practice rather than in spelling.
        for source in [center, bulk] {
            #expect(
                source.contains("pendingConfirmation = ") == false,
                "something assigned to pendingConfirmation directly"
            )
        }
    }

    /// The value still moves — through the box, from inside the centre only.
    @Test("Requesting and confirming still propagate through the nested observable")
    func requestingAndConfirmingStillPropagatesThroughTheNestedObservable() async throws {
        let harness = CenterHarness()

        #expect(harness.center.pendingConfirmation == nil)

        // Request → the getter reports it, and it is the request that was made.
        let request = try #require(
            harness.center.request(.uninstall(PackageTarget(Self.wget)!))
        )
        #expect(harness.center.pendingConfirmation == request)
        #expect(harness.center.pendingConfirmation?.displayCommand == "brew uninstall --formula wget")
        #expect(harness.launcher.launchCount == 0, "the request enqueued before it was answered")

        // Confirm → cleared, and exactly what was shown is submitted.
        let items = harness.center.confirm(request)
        await harness.settle()
        #expect(harness.center.pendingConfirmation == nil)
        #expect(items.map(\.arguments) == [["uninstall", "--formula", "wget"]])
        try await harness.finish(call: 0)

        // Decline → cleared, and nothing is submitted for it.
        let second = try #require(harness.center.request(.uninstall(PackageTarget(Self.git)!)))
        #expect(harness.center.pendingConfirmation == second)
        harness.center.decline(second)
        await harness.settle()
        #expect(harness.center.pendingConfirmation == nil)
        #expect(harness.center.items.count == 1, "a declined confirmation enqueued something")
    }

    /// Observation has to survive the extra hop, or the sheet stops updating.
    ///
    /// `withObservationTracking` reads the **computed** property, so what is
    /// registered is the box's storage one level down. If the box were not
    /// `@Observable`, or if the getter did not read it, this would never fire.
    @Test("Observation propagates through the nested observable read")
    func observationPropagatesThroughTheNestedRead() async throws {
        let harness = CenterHarness()
        let changed = Flag()

        withObservationTracking {
            _ = harness.center.pendingConfirmation
        } onChange: {
            changed.set()
        }

        #expect(changed.isSet == false, "the tracker fired before anything changed")
        _ = harness.center.request(.uninstall(PackageTarget(Self.wget)!))
        await harness.settle()

        #expect(changed.isSet, "a pending confirmation did not wake its observers")
    }

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
    }
}
