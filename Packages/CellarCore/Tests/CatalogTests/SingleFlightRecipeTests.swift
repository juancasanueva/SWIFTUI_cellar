import Synchronization
import Testing

/// The compiler assumption the whole D3 single-flight recipe rests on.
///
/// D3 vacates the coalescing slot from a `defer` **inside** the task body rather
/// than after `await task.value` returns to the creator. That is only sound if
/// the `defer` has already run by the time *any* awaiter of `task.value`
/// resumes — otherwise a joiner could still observe the settled task in the slot
/// and be handed its stale result, which is exactly the defect D3 removes.
///
/// Nothing in the language guide spells that ordering out, so it is probed here
/// directly. If this suite fails under the project toolchain the recipe is
/// unsound and D3 has to be redesigned before any production edit.
@Suite("Single-flight recipe assumption", .timeLimit(.minutes(1)))
struct SingleFlightRecipeTests {
    @Test("A task's deferred cleanup has run when its creator's await resumes")
    func deferHasRunWhenCreatorResumes() async {
        let vacated = Flag()

        let task = Task { () -> Int in
            defer { vacated.set() }
            return 7
        }

        let value = await task.value

        #expect(value == 7)
        #expect(vacated.isSet, "the defer had not run when task.value returned")
    }

    @Test("A task's deferred cleanup has run when a joiner's await resumes")
    func deferHasRunWhenJoinerResumes() async {
        let gate = Gate()
        let vacated = Flag()

        let task = Task { () -> Int in
            defer { vacated.set() }
            await gate.wait()
            return 7
        }

        // Two joiners attach *before* the body can finish, so each observes the
        // flag at the instant its own `await task.value` resumes.
        let firstJoiner = Task { (await task.value, vacated.isSet) }
        let secondJoiner = Task { (await task.value, vacated.isSet) }
        await gate.waitForWaiters(atLeast: 1)
        gate.open()

        for joiner in [firstJoiner, secondJoiner] {
            let (value, wasVacated) = await joiner.value
            #expect(value == 7)
            #expect(wasVacated, "a joiner resumed before the task's defer had run")
        }
    }

    @Test("An actor-isolated task vacates its own slot before any joiner resumes")
    func actorIsolatedTaskVacatesBeforeJoinersResume() async {
        let probe = SingleFlightProbe()
        let gate = Gate()

        // Exactly D3's shape: creation and slot assignment in one actor turn, the
        // slot keyed by a token, the `defer` vacating from inside the body.
        let creator = Task { await probe.acquire(gate: gate) }
        await probe.waitForSlot()
        let firstJoiner = Task { await probe.acquire(gate: gate) }
        let secondJoiner = Task { await probe.acquire(gate: gate) }
        await gate.waitForWaiters(atLeast: 1)
        gate.open()

        let creatorOutcome = await creator.value
        #expect(creatorOutcome.value == 42)
        #expect(creatorOutcome.slotWasVacant, "the creator resumed with its own task still in the slot")

        for joiner in [firstJoiner, secondJoiner] {
            let outcome = await joiner.value
            #expect(outcome.value == 42)
            #expect(outcome.slotWasVacant, "a joiner resumed with settled work still in the slot")
        }

        // Only one body ran: the joiners genuinely coalesced rather than racing.
        #expect(await probe.bodyCount == 1)
    }
}

// MARK: - Probe

/// A stripped-down copy of the D3 slot, with no sync engine attached.
private actor SingleFlightProbe {
    struct Outcome: Sendable {
        let value: Int
        /// Whether the slot was already empty when this caller resumed.
        let slotWasVacant: Bool
    }

    private var inFlight: (token: Int, task: Task<Int, Never>)?
    private var nextToken = 0
    private(set) var bodyCount = 0

    var hasSlot: Bool { inFlight != nil }

    nonisolated func waitForSlot() async {
        var attempts = 0
        while await !hasSlot, attempts < 10_000 {
            attempts += 1
            await Task.yield()
        }
    }

    func acquire(gate: Gate) async -> Outcome {
        if let current = inFlight {
            let value = await current.task.value
            return Outcome(value: value, slotWasVacant: inFlight == nil)
        }

        nextToken += 1
        let token = nextToken
        let task = Task {
            defer { self.vacate(token) }
            self.bodyCount += 1
            await gate.wait()
            return 42
        }
        inFlight = (token, task)

        let value = await task.value
        return Outcome(value: value, slotWasVacant: inFlight == nil)
    }

    /// A token-keyed vacate can only ever empty its *own* entry.
    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }
}
