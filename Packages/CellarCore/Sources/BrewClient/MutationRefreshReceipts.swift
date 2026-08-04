import DiskUsage
import Foundation

public struct MutationOperationToken: Sendable, Hashable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum RefreshDomain: Sendable, Hashable {
    case taps
    case installedInventory
    case services
    case diskUsage
}

public struct MutationTerminalEvent: Sendable, Equatable {
    public let token: MutationOperationToken
    public let domain: RefreshDomain
    public let installationURL: URL
    public let diskAreas: Set<DiskArea>

    public init(
        token: MutationOperationToken,
        domain: RefreshDomain,
        installationURL: URL,
        diskAreas: Set<DiskArea> = []
    ) {
        self.token = token
        self.domain = domain
        self.installationURL = installationURL
        self.diskAreas = diskAreas
    }
}

public enum RefreshResult: Sendable, Equatable {
    case refreshed
    case failed
    case brewUnavailable
    case installationChanged
    case cancelled
    case teardown
}

public struct RefreshReceipt: Sendable, Equatable {
    public let token: MutationOperationToken
    public let results: [RefreshDomain: RefreshResult]

    public init(token: MutationOperationToken, results: [RefreshDomain: RefreshResult]) {
        self.token = token
        self.results = results
    }
}

/// Settles operation/domain refresh expectations exactly once.
public actor MutationRefreshRegistry {
    private struct Entry {
        let expected: Set<RefreshDomain>
        var results: [RefreshDomain: RefreshResult] = [:]
        var waiter: CheckedContinuation<RefreshReceipt?, Never>?

        var isComplete: Bool { Set(results.keys) == expected }
    }

    private var entries: [MutationOperationToken: Entry] = [:]
    private var cancelledBeforeWait: Set<MutationOperationToken> = []

    public init() {}

    public func register(_ token: MutationOperationToken, domains: Set<RefreshDomain>) {
        guard entries[token] == nil, !domains.isEmpty else { return }
        entries[token] = Entry(expected: domains)
    }

    public func isRegistered(_ token: MutationOperationToken) -> Bool {
        entries[token] != nil
    }

    @discardableResult
    public func complete(_ event: MutationTerminalEvent, with result: RefreshResult) -> Bool {
        guard var entry = entries[event.token],
              entry.expected.contains(event.domain),
              entry.results[event.domain] == nil
        else { return false }

        entry.results[event.domain] = result
        entries[event.token] = entry
        resolveIfReady(event.token)
        return true
    }

    public func wait(for token: MutationOperationToken) async -> RefreshReceipt? {
        if Task.isCancelled {
            entries[token] = nil
            return nil
        }
        guard let entry = entries[token] else { return nil }
        if entry.isComplete {
            entries[token] = nil
            return RefreshReceipt(token: token, results: entry.results)
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if cancelledBeforeWait.remove(token) != nil || Task.isCancelled {
                    entries[token] = nil
                    continuation.resume(returning: nil)
                    return
                }
                guard var current = entries[token] else {
                    continuation.resume(returning: nil)
                    return
                }
                current.waiter = continuation
                entries[token] = current
                resolveIfReady(token)
            }
        } onCancel: {
            Task { await self.cancelWaiter(for: token) }
        }
    }

    public func shutdown() {
        for token in Array(entries.keys) {
            guard var entry = entries[token] else { continue }
            for domain in entry.expected where entry.results[domain] == nil {
                entry.results[domain] = .teardown
            }
            entries[token] = entry
            resolveIfReady(token)
        }
    }

    private func cancelWaiter(for token: MutationOperationToken) {
        guard let entry = entries.removeValue(forKey: token) else {
            cancelledBeforeWait.insert(token)
            return
        }
        entry.waiter?.resume(returning: nil)
    }

    private func resolveIfReady(_ token: MutationOperationToken) {
        guard let entry = entries[token], entry.isComplete, let waiter = entry.waiter else { return }
        entries[token] = nil
        waiter.resume(returning: RefreshReceipt(token: token, results: entry.results))
    }
}
