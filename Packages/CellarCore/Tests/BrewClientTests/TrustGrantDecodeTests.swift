import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// `package-trust` PT1 and PT4 — what a per-package trust report decodes into,
/// and what a Homebrew that cannot answer decodes into instead.
@Suite("Per-package trust decoding")
struct TrustGrantDecodeTests {
    // MARK: - PT4 :254-260, :262-268 — the measured payload, verbatim

    /// The fixture is the **captured** payload (Engram `#7764`), not a sketch of
    /// one. Every expectation below is a property of those exact bytes.
    @Test("The verbatim Homebrew payload decodes every namespace")
    func theVerbatimHomebrewPayloadDecodesEveryNamespace() async throws {
        let ledger = try await TrustGrantDecoder.decode(TrustGrantFixture.measuredPayload)

        // All four published namespaces decode, entry-for-entry and in order.
        #expect(ledger.taps == TrustGrantFixture.measuredTaps)
        #expect(ledger.formulae == TrustGrantFixture.measuredFormulae)
        #expect(ledger.casks == TrustGrantFixture.measuredCasks)
        #expect(ledger.commands == [])
        #expect(ledger.entryCount == TrustGrantFixture.measuredEntryCount)

        // The URL-shaped entry survives whole: four slashes, no owner/repo shape,
        // and nothing here is allowed to normalize or split it (PT3 :203-209).
        #expect(ledger.formulae.contains("https://github.com/cloudmanic/spice-edit/spice-edit"))
        // …and a package name may carry `@`.
        #expect(ledger.casks.contains("guria/tap/nehir@rc"))
        // …and the same identifier really is in both namespaces.
        #expect(ledger.formulae.contains("gentleman-programming/tap/engram"))
        #expect(ledger.casks.contains("gentleman-programming/tap/engram"))

        // The payload declared `commands`, empty. All four keys were present.
        #expect(ledger.declaredNamespaces == ["taps", "formulae", "casks", "commands"])
        #expect(ledger.unmodelled.isEmpty)

        // An absent key is an empty list, not a decode failure — and it is
        // reported as **undeclared**, which is a different fact from empty.
        let sparse = try await TrustGrantDecoder.decode(
            Data("{\"formulae\":[\"acme/tools/widget\"]}".utf8)
        )
        #expect(sparse.formulae == ["acme/tools/widget"])
        #expect(sparse.casks.isEmpty)
        #expect(sparse.taps.isEmpty)
        #expect(sparse.commands.isEmpty)
        #expect(sparse.declaredNamespaces == ["formulae"])
        #expect(sparse.entryCount == 1)
    }

    // MARK: - PT1 :91-97 — a brew that cannot answer reported nothing, not zero

    /// **R4.** The whole reason the state is three-valued: a Homebrew with no
    /// `trust` verb has reported *nothing*. Rendering that as "0 grants" would
    /// state a fact about this Mac that nobody measured.
    @Test("An unanswered brew is unreported, never zero grants")
    func anUnansweredBrewIsUnreportedNotZeroGrants() async throws {
        // Each acquisition failure is typed, and distinctly so.
        await #expect(throws: TrustGrantError.malformedJSON) {
            try await TrustGrantDecoder.decode(Data("not json".utf8))
        }
        await #expect(throws: TrustGrantError.nonObjectEnvelope) {
            try await TrustGrantDecoder.decode(Data("[\"acme/tools/widget\"]".utf8))
        }
        #expect(throws: TrustGrantError.blankOutput) {
            try TrustGrantPayload.payload(
                from: [LogLine(stream: .stdout, text: "   ", sequence: 0)],
                exit: BrewExit(status: 0, reason: .exited)
            )
        }
        #expect {
            try TrustGrantPayload.payload(
                from: [LogLine(stream: .stderr, text: "Error: Unknown command: trust", sequence: 0)],
                exit: BrewExit(status: 1, reason: .exited)
            )
        } throws: { error in
            (error as? TrustGrantError)
                == .commandFailed(status: 1, message: "Error: Unknown command: trust")
        }

        // …and every one of them settles to `unreported` on a machine that has
        // never had a good answer. Not `noGrants`, not an empty ledger.
        let failures: [TrustGrantError] = [
            .commandFailed(status: 1, message: "Error: Unknown command: trust"),
            .brewUnavailable,
            .blankOutput,
            .malformedJSON,
            .nonObjectEnvelope,
            .cancelled
        ]
        for failure in failures {
            let settled = TrustGrantState.settled(.failure(failure), keeping: .unreported)
            #expect(settled == .unreported, "\(failure) reported something")
            #expect(settled.ledger == nil, "\(failure) produced a grant set")
            #expect(settled.entryCount == nil, "\(failure) produced a count")
        }

        // A brew that *did* answer, with nothing in it, is a different value.
        let answered = try await TrustGrantDecoder.decode(
            Data("{\"taps\":[],\"formulae\":[],\"casks\":[],\"commands\":[]}".utf8)
        )
        let empty = TrustGrantState.settled(.success(answered), keeping: .unreported)
        #expect(empty == .noGrants)
        #expect(empty != .unreported, "a reported-empty report collapsed into unreported")
        #expect(empty.entryCount == 0)
        #expect(TrustGrantState.unreported.entryCount == nil)
    }

    // MARK: - DD-1 — one representation of "nothing", not two

    @Test("An empty ledger cannot be granted")
    func anEmptyLedgerCannotBeGranted() {
        #expect(TrustGrantState.reported(TrustGrantLedger()) == .noGrants)

        // No construction path yields `granted` carrying a ledger with no entry
        // in it — which is what would make `granted` and `noGrants` two names
        // for the same fact.
        let nothings = [
            TrustGrantLedger(),
            TrustGrantLedger(commands: []),
            TrustGrantLedger(unmodelled: [:]),
            TrustGrantLedger(declaredNamespaces: ["taps", "formulae", "casks", "commands"])
        ]
        for ledger in nothings {
            #expect(ledger.entryCount == 0)
            #expect(TrustGrantState.reported(ledger) == .noGrants)
            #expect(TrustGrantState.settled(.success(ledger), keeping: .unreported) == .noGrants)
            #expect(TrustGrantState.reported(ledger).ledger == nil)
        }

        // Triangulated the other way: a single entry in **any** namespace is a
        // report with something in it, and it is carried through intact. The
        // `taps` namespace counts here because an orphan tap grant is a grant
        // this surface must show (PT8 :435-441); it just never becomes a
        // package count (PT4 :246-252).
        let somethings = [
            TrustGrantLedger(formulae: ["acme/tools/widget"]),
            TrustGrantLedger(casks: ["acme/tools/widget"]),
            TrustGrantLedger(taps: ["acme/tools"]),
            TrustGrantLedger(commands: ["acme/tools/thing"]),
            TrustGrantLedger(unmodelled: ["plugins": ["acme/tools/thing"]])
        ]
        for ledger in somethings {
            #expect(ledger.entryCount == 1)
            #expect(TrustGrantState.reported(ledger) == .granted(ledger))
            #expect(TrustGrantState.reported(ledger).ledger == ledger)
        }
    }

    // MARK: - PT4 :270-276 — an unmodelled namespace is counted, not discarded

    /// **B5.** Forward compatibility that *drops* the key would make the
    /// accounting's "these totals sum to the entries decoded" claim false the
    /// day Homebrew publishes a fifth namespace, and it would do so silently.
    @Test("An unmodelled namespace is counted, never discarded")
    func anUnmodelledNamespaceIsCountedNotDiscarded() async throws {
        let ledger = try await TrustGrantDecoder.decode(Data("""
        {"taps":["acme/tools"],"formulae":["acme/tools/widget"],\
        "casks":["other/tools/desk"],"commands":["acme/tools/thing"],\
        "plugins":["acme/tools/plug","other/tools/plug"]}
        """.utf8))

        // The decode succeeded and the four known namespaces are exactly as usual.
        #expect(ledger.taps == ["acme/tools"])
        #expect(ledger.formulae == ["acme/tools/widget"])
        #expect(ledger.casks == ["other/tools/desk"])
        #expect(ledger.commands == ["acme/tools/thing"])

        // …and the fifth key's entries are retained, verbatim, for the "other"
        // category rather than thrown away.
        #expect(ledger.unmodelled == ["plugins": ["acme/tools/plug", "other/tools/plug"]])
        #expect(ledger.entryCount == 6)
        #expect(ledger.declaredNamespaces
            == ["taps", "formulae", "casks", "commands", "plugins"])

        // A key whose value is not a list of strings is not a grant namespace at
        // all; it carries no entry, so counting it is not owed.
        let scalar = try await TrustGrantDecoder.decode(Data("""
        {"formulae":["acme/tools/widget"],"schema":1}
        """.utf8))
        #expect(scalar.unmodelled.isEmpty)
        #expect(scalar.entryCount == 1)

        // PT4 :262-268 — present-and-empty is a report of nothing in that
        // namespace, which is a different fact from a namespace nobody sent.
        let declared = try await TrustGrantDecoder.decode(
            Data("{\"formulae\":[\"acme/tools/widget\"],\"commands\":[]}".utf8)
        )
        let undeclared = try await TrustGrantDecoder.decode(
            Data("{\"formulae\":[\"acme/tools/widget\"]}".utf8)
        )
        #expect(declared.commands.isEmpty)
        #expect(undeclared.commands.isEmpty)
        #expect(declared.declaresCommands)
        #expect(undeclared.declaresCommands == false)
        #expect(declared != undeclared, "an empty commands array was indistinguishable from no key")
        #expect(declared.entryCount == undeclared.entryCount)
    }
}
