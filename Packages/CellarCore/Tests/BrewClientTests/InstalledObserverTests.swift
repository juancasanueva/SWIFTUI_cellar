import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog
@testable import DiskUsage

/// Construction-level cover for the one untested-by-design adapter.
///
/// It deliberately does **not** exercise CoreServices delivery — no file is
/// touched, no event is awaited, and the test passes whether or not the machine
/// running it can actually watch the temporary roots (design D12). What it does
/// pin is the ownership rule the adapter got wrong: `changes()` was not
/// idempotent, so a second call silently abandoned the first stream and its
/// retained box.
@Suite("Installed change observer", .timeLimit(.minutes(1)))
struct InstalledObserverTests {
    @MainActor
    @Test("One root stream fans out to installed and starts disk revalidation")
    func oneStreamFansOutToBothConsumers() async {
        let observer = FakeInstalledChangeObserver()
        let installedSignals = Counter()
        let scanner = RecordingDiskUsageScanner()
        let store = DiskUsageStore(cache: ObserverMemoryDiskUsageCache())
        let roots = HomebrewRoots(
            installation: TestInstallation.appleSilicon,
            userCacheDirectory: FileManager.default.temporaryDirectory
        )
        store.startScan(roots: roots, scanner: scanner)
        await TestPoll.until(scanner.callCount == 1)
        let coordinator = DiskUsageRefreshCoordinator(store: store)
        let fanout = HomebrewChangeFanout(
            observer: observer,
            installedChanged: { installedSignals.increment() },
            diskChanged: { areas in coordinator.invalidate(areas) }
        )
        let task = Task { await fanout.run() }
        while observer.changesCallCount == 0 { await Task.yield() }

        observer.emit()
        await TestPoll.until(installedSignals.value == 1 && scanner.callCount == 2)

        #expect(observer.changesCallCount == 1)
        #expect(installedSignals.value == 1)
        #expect(scanner.callCount == 2)
        #expect(store.invalidatedAreas == [.cellar, .caskroom])
        #expect(scanner.roots == [roots.identity, roots.identity])
        observer.finish()
        await task.value
        store.cancel()
    }

    @MainActor
    @Test("Production gates keep disk-only invalidation out of Installed refresh")
    func diskMutationRevalidatesWithoutInstalledRefresh() async {
        let scanner = RecordingDiskUsageScanner()
        let diskStore = DiskUsageStore(cache: ObserverMemoryDiskUsageCache())
        let roots = HomebrewRoots(
            installation: TestInstallation.appleSilicon,
            userCacheDirectory: FileManager.default.temporaryDirectory
        )
        diskStore.startScan(roots: roots, scanner: scanner)
        await TestPoll.until(scanner.callCount == 1)

        let installedLauncher = RecordingProcessLauncher()
        let installedStore = InstalledStore(
            source: BrewInfoPayloadSource(launcher: installedLauncher)
        )
        let installedGate = InstalledMutationGate()
        let diskGate = InstalledMutationGate()
        let gates = MutationGates([
            (.installedInventory, installedGate),
            (.diskUsage, diskGate)
        ])
        let installedCoordinator = InstalledRefreshCoordinator(
            store: installedStore,
            mutations: installedGate
        )
        let diskCoordinator = DiskUsageRefreshCoordinator(
            store: diskStore,
            mutations: diskGate
        )
        let installedLoop = Task { await installedCoordinator.run() }
        let diskLoop = Task { await diskCoordinator.run() }
        await installedCoordinator.refresh(using: TestInstallation.appleSilicon)
        #expect(installedLauncher.launchCount == 1)

        gates.begin(.diskUsage)
        gates.end(
            .diskUsage,
            token: MutationOperationToken(),
            installationURL: TestInstallation.appleSilicon.executableURL,
            diskAreas: [.caskroom]
        )

        await TestPoll.until(scanner.callCount == 2)
        #expect(scanner.callCount == 2)
        #expect(diskStore.invalidatedAreas == [.caskroom])
        #expect(installedLauncher.launchCount == 1)

        gates.begin(.installedInventory)
        gates.end(
            .installedInventory,
            token: MutationOperationToken(),
            installationURL: TestInstallation.appleSilicon.executableURL
        )
        await TestPoll.until(installedLauncher.launchCount == 2)
        #expect(installedLauncher.launchCount == 2)
        #expect(installedLauncher.specs.allSatisfy {
            $0.arguments == ["info", "--installed", "--json=v2"]
        })

        installedGate.shutdown()
        diskGate.shutdown()
        await installedLoop.value
        await diskLoop.value
        diskStore.cancel()
    }

    /// An observer over a throwaway prefix, so nothing real is watched.
    private static func observer() throws -> (FSEventsInstalledObserver, URL) {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-observer-\(UUID().uuidString)", isDirectory: true)
        for leaf in ["Cellar", "Caskroom", "bin"] {
            try FileManager.default.createDirectory(
                at: prefix.appendingPathComponent(leaf, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let installation = BrewInstallation(
            executableURL: prefix.appendingPathComponent("bin/brew"),
            prefix: .appleSilicon,
            version: BrewVersion(major: 6, minor: 0, patch: 14)
        )
        return (FSEventsInstalledObserver(installation: installation), prefix)
    }

    @Test("A second changes() finishes the first stream instead of abandoning it")
    func aSecondChangesFinishesTheFirst() async throws {
        let (observer, prefix) = try Self.observer()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let superseded = observer.changes()
        let survivor = observer.changes()

        // The superseded stream is finished, so draining it completes on its
        // own. Before the fix it hung forever on a stream nothing fed.
        let supersededDrained = Mutex(false)
        let firstDrain = Task {
            for await _ in superseded {}
            supersededDrained.withLock { $0 = true }
        }
        await TestPoll.until(supersededDrained.withLock { $0 })
        #expect(
            supersededDrained.withLock { $0 },
            "the superseded stream was abandoned rather than finished"
        )
        firstDrain.cancel()

        // Exactly one stream is left live: the survivor does not finish on its
        // own just because a sibling was torn down.
        let survivorDrained = Mutex(false)
        let secondDrain = Task {
            for await _ in survivor {}
            survivorDrained.withLock { $0 = true }
        }
        for _ in 0..<200 { await Task.yield() }
        #expect(
            survivorDrained.withLock { $0 } == false,
            "the surviving stream was finished along with the superseded one"
        )

        // Teardown re-enters `stop()` through `onTermination`. The mutex is not
        // recursive, so doing it under the lock would trap rather than fail.
        secondDrain.cancel()
        await secondDrain.value
        #expect(survivorDrained.withLock { $0 })
    }

    /// Three calls, not two: "last caller wins" has to hold for every previous
    /// stream, not merely for the immediately preceding one.
    @Test("Every superseded stream is finished, not only the last")
    func everySupersededStreamIsFinished() async throws {
        let (observer, prefix) = try Self.observer()
        defer { try? FileManager.default.removeItem(at: prefix) }

        let first = observer.changes()
        let second = observer.changes()
        let third = observer.changes()

        let firstDrained = Mutex(false)
        let firstDrain = Task {
            for await _ in first {}
            firstDrained.withLock { $0 = true }
        }
        let secondDrained = Mutex(false)
        let secondDrain = Task {
            for await _ in second {}
            secondDrained.withLock { $0 = true }
        }
        await TestPoll.until(firstDrained.withLock { $0 } && secondDrained.withLock { $0 })

        #expect(firstDrained.withLock { $0 }, "the oldest stream was abandoned")
        #expect(secondDrained.withLock { $0 }, "the middle stream was abandoned")
        firstDrain.cancel()
        secondDrain.cancel()

        // And the newest one is the one still live.
        let survivorDrained = Mutex(false)
        let survivor = Task {
            for await _ in third {}
            survivorDrained.withLock { $0 = true }
        }
        for _ in 0..<200 { await Task.yield() }
        #expect(survivorDrained.withLock { $0 } == false)

        survivor.cancel()
        await survivor.value
    }
}

private final class RecordingDiskUsageScanner: DiskUsageScanning, @unchecked Sendable {
    private let recordedRoots = Mutex<[DiskRootsIdentity]>([])

    var callCount: Int { recordedRoots.withLock(\.count) }
    var roots: [DiskRootsIdentity] { recordedRoots.withLock { $0 } }

    func scan(
        roots: HomebrewRoots,
        formulaLinks: [PackageID: FormulaLinkState]
    ) async -> DiskUsageEventStream {
        recordedRoots.withLock { $0.append(roots.identity) }
        return AsyncThrowingStream { _ in }
    }
}

private actor ObserverMemoryDiskUsageCache: DiskUsageCaching {
    func load() throws -> DiskUsageSnapshot? { nil }
    func save(_ snapshot: DiskUsageSnapshot) throws {}
}
