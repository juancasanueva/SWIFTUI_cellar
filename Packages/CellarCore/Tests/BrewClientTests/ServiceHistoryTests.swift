import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// What the four service verbs write to the durable history
/// (installation-history IH1 sc5–sc6, operation-activity OA6 sc6).
///
/// **The product ruling, settled before this was written** (user, 2026-08-03,
/// Engram `#7180` a): service toggles **do** write history. All four verbs each
/// write exactly one entry with a **null package identity** and a typed service
/// verb. That honours IH1 as written — the terminal funnel writes by
/// construction — and keeps one auditable trail of everything Cellar submitted.
///
/// The accepted cost is a chatty history under repeated toggling. It is asserted
/// here rather than papered over: five start/stop pairs produce ten entries, and
/// nothing collapses them.
@MainActor
@Suite("Service history", .timeLimit(.minutes(1)))
struct ServiceHistoryTests {
    private static func target(_ name: String) throws -> ServiceTarget {
        try #require(ServiceTarget(name: name))
    }

    // MARK: - IH1 sc5, OA6 sc6 — one entry each, with no package identity

    @Test("Each service verb writes one entry with a null package identity")
    func eachServiceVerbWritesOneEntryWithANullPackageIdentity() async throws {
        let harness = CenterHarness()
        let atuin = try Self.target("atuin")
        let commands = ServiceCommand.allVerbs(for: atuin)

        for command in commands {
            let item = harness.center.submit(command)
            await harness.launcher.waitForLaunches(atLeast: harness.center.items.count)
            #expect(item.isTerminal == false)
        }
        for index in 0..<commands.count { try await harness.finish(call: index) }

        // Four operations, four entries — never zero, never two.
        #expect(harness.recorder.drafts.count == 4)

        let byVerb = Dictionary(
            harness.recorder.drafts.map { ($0.verb, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(
            Set(byVerb.keys) == ["serviceStart", "serviceRun", "serviceStop", "serviceRestart"]
        )

        for (verb, argv) in [
            ("serviceStart", ["services", "start", "atuin"]),
            ("serviceRun", ["services", "run", "atuin"]),
            ("serviceStop", ["services", "stop", "atuin"]),
            ("serviceRestart", ["services", "restart", "atuin"])
        ] {
            let draft = try #require(byVerb[verb], "no entry for \(verb)")
            #expect(draft.argv == argv, "\(verb) recorded the wrong argv")
            #expect(draft.outcome == .succeeded)
            #expect(draft.commandText == argv.joined(separator: " "))

            // The claim IH1 makes hardest: a **null** package identity, no
            // version-from, no version-to, and `atuin` never stored as a
            // package identity.
            #expect(draft.packageID == nil, "\(verb) stored a package identity")
            #expect(draft.versions == nil, "\(verb) stored a version transition")
        }

        #expect(
            harness.recorder.drafts.allSatisfy { $0.packageID?.name != "atuin" },
            "the service name was stored as a package identity"
        )
        #expect(harness.recorder.drafts.allSatisfy { $0.packageID == nil })
    }

    /// A `.noChange` terminal is recorded on exactly the same terms as any
    /// other: one entry, its own outcome, and no pretending it was a success.
    @Test("A no-change outcome records one entry naming itself")
    func aNoChangeOutcomeRecordsOneEntryNamingItself() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(service: .start(try Self.target("atuin")))
        await harness.launcher.waitForLaunches(atLeast: 1)
        harness.launcher.launchedProcesses[0].emitStdout(
            "Service `atuin` already started, use `brew services restart atuin` to restart.\n"
        )
        await harness.settle()
        try await harness.finish(call: 0)

        #expect(item.outcome == .noChange)
        #expect(harness.recorder.drafts.count == 1)
        let draft = try #require(harness.recorder.drafts.first)
        #expect(draft.outcome == .noChange)
        #expect(draft.verb == "serviceStart")
        #expect(draft.packageID == nil)
    }

    // MARK: - IH1 sc6 — repetition is never collapsed

    /// The chatty-history cost, accepted and recorded (ruling #7180 a). Ten
    /// operations produce ten entries: nothing is deduplicated, coalesced,
    /// throttled or netted out into "no change overall".
    @Test("Repeated toggling appends one entry per operation")
    func repeatedTogglingAppendsOneEntryPerOperation() async throws {
        let harness = CenterHarness()
        let atuin = try Self.target("atuin")
        var expectedVerbs: [String] = []

        for _ in 0..<5 {
            for command in [ServiceCommand.start(atuin), .stop(atuin)] {
                harness.center.submit(command)
                expectedVerbs.append(command.verb)
                await harness.launcher.waitForLaunches(atLeast: harness.center.items.count)
                try await harness.finish(call: harness.center.items.count - 1)
            }
        }

        #expect(harness.recorder.drafts.count == 10, "entries were collapsed or netted out")
        #expect(harness.recorder.drafts.map(\.verb) == expectedVerbs, "submission order was lost")
        #expect(
            expectedVerbs == Array(repeating: ["serviceStart", "serviceStop"], count: 5).flatMap { $0 }
        )
        // Ten distinct entries, not one row with a count.
        #expect(Set(harness.recorder.drafts.map(\.id)).count == 10)
    }

    /// The guard from Phase 12 does not swallow entries either: a **refused**
    /// submission never reached the queue, so it must produce no entry at all —
    /// exactly one entry per operation that actually ran.
    @Test("A refused duplicate submission writes no entry of its own")
    func aRefusedDuplicateWritesNoEntry() async throws {
        let harness = CenterHarness()
        let atuin = try Self.target("atuin")

        let first = harness.center.submit(service: .start(atuin))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let refused = harness.center.submit(service: .stop(atuin))
        await harness.settle()
        #expect(refused === first)

        try await harness.finish(call: 0)

        #expect(harness.recorder.drafts.count == 1, "the refused submission wrote an entry")
        #expect(harness.recorder.drafts.first?.verb == "serviceStart")
    }
}
