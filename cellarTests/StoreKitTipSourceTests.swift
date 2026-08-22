//
//  StoreKitTipSourceTests.swift
//  cellarTests
//

import Darwin
import Foundation
import StoreKitTest
import Testing
import TipJar

@testable import cellar

/// A lock held **across processes**, for the length of one StoreKit test.
///
/// `@Suite(.serialized)` serializes a suite within one process, and that is not
/// enough here. The shared `cellar` scheme marks the test target
/// `parallelizable = "YES"`, and the scheme is a not-touched binding of this
/// change — so two `cellarTests` worker processes run at the same time, and both
/// talk to the **same** StoreKit agent environment under
/// `~/Library/Caches/com.apple.storekitagent/Octane/<bundle-id>/`. One worker's
/// `clearTransactions()` then deletes the leftover the other worker had just
/// seeded, and the drain test fails for a reason that has nothing to do with the
/// code it is testing.
///
/// Measured, not assumed: without this the drain test failed on the second
/// worker on every run while passing on the first — and `xcodebuild` still
/// printed `** TEST SUCCEEDED **`, which is exactly the silent false-green the
/// probes warned about (`probes.md`, conclusion 4).
///
/// Non-blocking with a bounded wait rather than a blocking `flock`, so a stuck
/// peer costs a failed test rather than a hung suite.
enum StoreKitAgentLock {
    private static var path: String {
        NSTemporaryDirectory() + "cellar-storekit-agent.lock"
    }

    static func withLock<T>(_ body: () async throws -> T) async rethrows -> T? {
        guard let descriptor = await acquire() else {
            Issue.record("the StoreKit agent lock was never granted; another worker is stuck")
            return nil
        }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try await body()
    }

    private static func acquire() async -> Int32? {
        let descriptor = open(path, O_CREAT | O_RDWR, 0o666)
        guard descriptor >= 0 else { return nil }

        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while ContinuousClock.now < deadline {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
            try? await Task.sleep(for: .milliseconds(20))
        }
        close(descriptor)
        return nil
    }
}

/// Requirement 9's last scenario — "The conformer is proven against a real local
/// store" — driven headlessly by `SKTestSession`, with no Xcode scheme modified.
///
/// **Why this suite's RED is not admissible proof.** The StoreKit agent keeps a
/// persistent per-app test environment at
/// `~/Library/Caches/com.apple.storekitagent/Octane/<bundle-id>/` that survives
/// both the process and the `xcodebuild` invocation (probes U16/U19). A failure
/// here can therefore be caused by leftover state rather than by missing code,
/// and a pass can be caused by leftover state rather than by working code. The
/// binding consequence, and the rule every test below is written to:
///
/// > **No assertion may depend on a cold store.** Each test resets to the default
/// > state, disables dialogs and clears transactions first, and then asserts only
/// > on the effect of an action it performed itself.
///
/// In particular nothing here asserts "zero products without a configuration" —
/// that is precisely the assertion a leftover environment makes flaky, and it
/// tells us nothing about the conformer anyway.
///
/// `.serialized` because one StoreKit test environment is shared by the whole
/// process: two of these running at once would each be clearing the other's
/// transactions.
@Suite("StoreKit tip source", .serialized)
struct StoreKitTipSourceTests {
    /// The arrangement every test starts from. Order matters: the session has to
    /// exist before it can be reset, and transactions have to be cleared after the
    /// reset rather than before it.
    private static func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Tip")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// The unfinished tip transactions, once the agent has caught up.
    ///
    /// `buyProduct` and `finish()` both return before `Transaction.unfinished`
    /// reflects them, and on a machine running the whole suite that gap is wide
    /// enough to read the queue as it was a moment ago. Measured: the drain test
    /// passed in isolation and failed inside the full run at 0.03 s, which is an
    /// arrangement that had not landed yet rather than a drain that did not work.
    ///
    /// Bounded, and it returns whatever it last saw rather than throwing, so a
    /// genuine failure still fails on its own assertion with the real value
    /// attached instead of on a timeout with none.
    private static func unfinishedTipIDs(
        until satisfied: ([String]) -> Bool
    ) async -> [String] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var ids = await StoreKitTipSource.unfinishedTipIDs()
        while satisfied(ids) == false, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            ids = await StoreKitTipSource.unfinishedTipIDs()
        }
        return ids
    }

    // MARK: - The product resolves, and every field comes from the store

    @Test("The configured consumable resolves with a display price the store supplied")
    func theConfiguredConsumableResolvesWithADisplayPriceTheStoreSupplied() async throws {
        try await StoreKitAgentLock.withLock {
            let session = try Self.session()
            defer { session.clearTransactions() }

            let load = await StoreKitTipSource().loadTips()

            guard case .loaded(let products) = load else {
                Issue.record("the catalog did not load: \(load)")
                return
            }
            let product = try #require(products.first { $0.id == TipProductIDs.tip })
            #expect(products.count == 1, "something other than the one configured consumable resolved")
            #expect(product.displayName == "Tip", "the display name was not read from the store")
            #expect(
                product.description == "A one-off thank-you to the developer.",
                "the description was composed locally instead of read from the store"
            )
            // The **price** is asserted as a property, never as a literal: this app
            // may not carry a price string, and the configuration's tier is not a
            // string this test is allowed to know.
            #expect(product.displayPrice.isEmpty == false, "the surface would render no price at all")
            #expect(
                product.displayPrice.contains(TipProductIDs.tip) == false,
                "the price field was filled with something that is not a price"
            )
        }
    }

    // MARK: - A purchase completes, and finishes what it started

    @Test("Buying the tip completes and leaves nothing unfinished behind it")
    func buyingTheTipCompletesAndLeavesNothingUnfinishedBehindIt() async throws {
        try await StoreKitAgentLock.withLock {
            let session = try Self.session()
            defer { session.clearTransactions() }
            let source = StoreKitTipSource()

            guard case .loaded(let products) = await source.loadTips(),
                  let product = products.first else {
                Issue.record("the catalog did not load, so nothing was bought")
                return
            }

            let outcome = await source.purchase(product)

            #expect(outcome == .completed)
            #expect(outcome.recordsGratitude)
            // The unfinished set is read **after** a purchase this test performed
            // itself, so an empty answer here is the effect of `finish()` rather
            // than a property of a store that happened to start out clean.
            #expect(
                await Self.unfinishedTipIDs { $0.isEmpty }.isEmpty,
                "the consumable was left unfinished, so it will replay at every launch"
            )
        }
    }

    /// Twice, because the product is a consumable: a user who already gave may
    /// give again, and the second purchase must complete exactly like the first
    /// rather than being refused as already-owned.
    @Test("The consumable can be bought twice, and both are finished")
    func theConsumableCanBeBoughtTwiceAndBothAreFinished() async throws {
        try await StoreKitAgentLock.withLock {
            let session = try Self.session()
            defer { session.clearTransactions() }
            let source = StoreKitTipSource()

            guard case .loaded(let products) = await source.loadTips(),
                  let product = products.first else {
                Issue.record("the catalog did not load, so nothing was bought")
                return
            }

            let first = await source.purchase(product)
            let second = await source.purchase(product)

            #expect(first == .completed)
            #expect(second == .completed, "a second tip was refused, as if the consumable were owned")
            #expect(await Self.unfinishedTipIDs { $0.isEmpty }.isEmpty)
        }
    }

    // MARK: - The launch drain clears what a previous launch left

    @Test("Draining finishes a leftover this test seeded itself")
    func drainingFinishesALeftoverThisTestSeededItself() async throws {
        try await StoreKitAgentLock.withLock {
            let session = try Self.session()
            defer { session.clearTransactions() }
            let source = StoreKitTipSource()

            // Seed the leftover: buy the tip with finishing suppressed, which is
            // exactly the state a launch that was killed mid-purchase leaves behind.
            session.askToBuyEnabled = false
            guard case .loaded(let products) = await source.loadTips(),
                  let product = products.first else {
                Issue.record("the catalog did not load, so no leftover could be seeded")
                return
            }
            _ = try await session.buyProduct(productIdentifier: product.id)

            let seeded = await Self.unfinishedTipIDs { $0.contains(TipProductIDs.tip) }
            #expect(
                seeded.contains(TipProductIDs.tip),
                "the arrangement never produced an unfinished transaction, so the drain proves nothing"
            )

            await source.drainUnfinished()

            #expect(
                await Self.unfinishedTipIDs { $0.isEmpty }.isEmpty,
                "a leftover consumable survived the launch drain, so it replays forever"
            )
        }
    }
}
