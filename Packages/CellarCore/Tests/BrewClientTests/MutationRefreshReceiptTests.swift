import Foundation
import Testing

@testable import BrewClient

@Suite("Mutation refresh receipts", .timeLimit(.minutes(1)))
struct MutationRefreshReceiptTests {
    private let installationURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")

    @Test("A receipt completes only after every registered domain settles")
    func receiptWaitsForEveryDomain() async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps, .installedInventory])
        let waiter = Task { await registry.wait(for: token) }

        let tapsAccepted = await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        )
        #expect(tapsAccepted)
        #expect(await registry.isRegistered(token))

        let installedAccepted = await registry.complete(
            MutationTerminalEvent(
                token: token,
                domain: .installedInventory,
                installationURL: installationURL
            ),
            with: .refreshed
        )
        let receipt = try #require(await waiter.value)

        #expect(installedAccepted)
        #expect(receipt.token == token)
        #expect(receipt.results == [.taps: .refreshed, .installedInventory: .refreshed])
        #expect(await registry.isRegistered(token) == false)
    }

    @Test(
        "Every bounded refresh result is preserved in the keyed receipt",
        arguments: [
            RefreshResult.failed,
            .brewUnavailable,
            .installationChanged,
            .cancelled,
            .teardown
        ]
    )
    func boundedResultsSettle(result: RefreshResult) async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        await registry.register(token, domains: [.services])
        let waiter = Task { await registry.wait(for: token) }

        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .services, installationURL: installationURL),
            with: result
        ))
        let receipt = try #require(await waiter.value)
        #expect(receipt.results == [.services: result])
    }

    @Test("Duplicate and unknown completions are ignored")
    func duplicateAndUnknownCompletionsAreIgnored() async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        let unknown = MutationOperationToken()
        await registry.register(token, domains: [.taps, .installedInventory])

        #expect(await registry.complete(
            MutationTerminalEvent(token: unknown, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ) == false)
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .services, installationURL: installationURL),
            with: .refreshed
        ) == false)
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ))
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .failed
        ) == false)

        let waiter = Task { await registry.wait(for: token) }
        #expect(await registry.complete(
            MutationTerminalEvent(
                token: token,
                domain: .installedInventory,
                installationURL: installationURL
            ),
            with: .refreshed
        ))
        let receipt = try #require(await waiter.value)
        #expect(receipt.results[.taps] == .refreshed, "a duplicate rewrote the first result")
    }

    @Test("Completion before a consumer is retained, while unregistered events are discarded")
    func noConsumerPathsAreBounded() async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        let unregistered = MutationOperationToken()
        await registry.register(token, domains: [.taps])

        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ))
        #expect(await registry.complete(
            MutationTerminalEvent(
                token: unregistered,
                domain: .taps,
                installationURL: installationURL
            ),
            with: .refreshed
        ) == false)

        let receipt = try #require(await registry.wait(for: token))
        #expect(receipt.results == [.taps: .refreshed])
    }

    @Test("Cancelling a waiter removes its registration")
    func waiterCancellationRemovesRegistration() async {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps])
        let waiter = Task { await registry.wait(for: token) }

        waiter.cancel()
        #expect(await waiter.value == nil)
        #expect(await registry.isRegistered(token) == false)
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ) == false)
    }

    @Test("Registry shutdown resolves every outstanding domain as teardown")
    func shutdownResolvesOutstandingDomains() async throws {
        let registry = MutationRefreshRegistry()
        let first = MutationOperationToken()
        let second = MutationOperationToken()
        await registry.register(first, domains: [.taps, .installedInventory])
        await registry.register(second, domains: [.services])
        let firstWaiter = Task { await registry.wait(for: first) }
        let secondWaiter = Task { await registry.wait(for: second) }

        await registry.shutdown()

        let firstReceipt = try #require(await firstWaiter.value)
        let secondReceipt = try #require(await secondWaiter.value)
        #expect(firstReceipt.results == [.taps: .teardown, .installedInventory: .teardown])
        #expect(secondReceipt.results == [.services: .teardown])
    }
}
