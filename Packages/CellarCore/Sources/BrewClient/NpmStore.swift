import BrewProcess
import Catalog
import Foundation
import Observation

/// The npm inventory as the UI sees it, and the thing that pushes it into the
/// one merged inventory.
///
/// The single main-isolated crossing point on npm's read path: acquisition and
/// decoding both run below it, in SwiftPM's default `nonisolated` world, exactly
/// as `InstalledStore`'s do.
///
/// Two shapes are deliberately *not* copied from `InstalledStore`:
///
/// - there is no ordinal guard. `InstalledStore` needs one because two
///   `brew info` acquisitions can overlap and land out of order; here the two
///   reads are sequenced by this actor and each `refresh` awaits its own.
/// - the two reads are separate entry points rather than one. `ls -g` is local
///   and cheap; `outdated -g` needs the network and can be slow. Sharing a
///   trigger is exactly the cost the proposal names as the risk, so they never
///   share one.
@MainActor
@Observable
public final class NpmStore {
    /// What npm currently reports: the globals, and how current the outdated
    /// picture is.
    public private(set) var inventory: NpmInventory = .empty

    /// The failure of the most recent *listing*, if it failed.
    ///
    /// Kept apart from `inventory.outdated`, which carries the freshness of the
    /// **report**. A machine can perfectly well have a good listing and an
    /// unreachable registry, and the summary has to be able to say so.
    public private(set) var listingFailure: NpmInventoryError?

    /// Whether npm rows are currently contributing to the merged inventory.
    public private(set) var isContributing = false

    @ObservationIgnored private let installed: InstalledStore
    @ObservationIgnored private let source: any NpmPayloadSourcing
    @ObservationIgnored private let clock: any NpmClock

    public init(
        installed: InstalledStore,
        source: any NpmPayloadSourcing = NpmPayloadSource(),
        clock: any NpmClock = SystemNpmClock()
    ) {
        self.installed = installed
        self.source = source
        self.clock = clock
    }

    // MARK: - Reading

    /// Re-reads the global listing and pushes the result into the inventory.
    ///
    /// The freshness of the outdated report is carried across unchanged: a new
    /// listing says what is installed, not whether it is current, and resetting
    /// the report to `notChecked` on every listing would make a machine flicker
    /// between "up to date" and "not checked" for no reason the user caused.
    public func refreshListing(using environment: NpmEnvironment) async {
        let outcome = await Self.globals(from: source, using: environment)

        switch outcome {
        case .success(let packages):
            listingFailure = nil
            inventory = NpmInventory(packages: packages, outdated: inventory.outdated)
            publish()
        case .failure(let error):
            // The last good listing stays resident, on `InstalledStore`'s own
            // discipline: a transient failure must not empty the user's list.
            listingFailure = error
        }
    }

    /// Re-runs the outdated check and pushes the new offered versions through.
    public func refreshOutdated(using environment: NpmEnvironment) async {
        let outcome = await Self.outdated(from: source, using: environment)

        switch outcome {
        case .success(let records):
            inventory = NpmInventory(
                packages: inventory.packages,
                outdated: .fresh(records, at: clock.now())
            )
        case .failure(.cancelled):
            // Nothing went wrong and there is no answer. `failed` would name a
            // problem the user does not have.
            inventory = NpmInventory(
                packages: inventory.packages, outdated: .notChecked(.cancelled)
            )
        case .failure(let error):
            inventory = NpmInventory(packages: inventory.packages, outdated: .failed(error))
        }
        publish()
    }

    /// Reacts to a detection change: contribute when detected, withdraw
    /// otherwise.
    ///
    /// `disabled`, `absent`, `invalid` and `configuredPathMissing` all withdraw.
    /// They are four different things to *say*, and exactly the same thing to
    /// *do*: there is no npm, so there are no npm rows.
    public func apply(_ detection: NpmDetectionState) async {
        guard let environment = detection.environment else {
            withdraw()
            return
        }
        await refreshListing(using: environment)
    }

    /// Removes every npm row and resets to the pre-read state.
    public func withdraw() {
        inventory = .empty
        listingFailure = nil
        guard isContributing else { return }
        isContributing = false
        installed.clearContributions(from: .npm)
    }

    // MARK: - Publication

    /// Pushes the projection into the merged inventory.
    ///
    /// Every adoption, including the first, goes through `adopt(_:from:)`, so the
    /// merge rule has exactly one implementation and npm never assembles an
    /// inventory of its own.
    private func publish() {
        isContributing = true
        installed.adopt(inventory.installedPackages(), from: .npm)
    }

    // MARK: - Off the main actor

    private static func globals(
        from source: any NpmPayloadSourcing,
        using environment: NpmEnvironment
    ) async -> Result<[NpmGlobalPackage], NpmInventoryError> {
        do {
            let payload = try await source.installed(using: environment)
            return .success(try await NpmDecode.globals(payload))
        } catch {
            return .failure(error)
        }
    }

    private static func outdated(
        from source: any NpmPayloadSourcing,
        using environment: NpmEnvironment
    ) async -> Result<[String: NpmOutdatedRecord], NpmInventoryError> {
        do {
            let payload = try await source.outdated(using: environment)
            return .success(try await NpmDecode.outdated(payload))
        } catch {
            return .failure(error)
        }
    }
}

/// Decoding, off the caller's executor.
///
/// `@concurrent` rather than a plain `nonisolated func`: a synchronous
/// nonisolated call from an actor still runs *on* that actor, which is the
/// head-of-line block the whole design avoids — the same reason
/// `CatalogDecoder.decode` is written this way.
enum NpmDecode {
    @concurrent
    static func globals(_ data: Data) async throws(NpmInventoryError) -> [NpmGlobalPackage] {
        try NpmDecoder.globals(from: data)
    }

    @concurrent
    static func outdated(
        _ data: Data
    ) async throws(NpmInventoryError) -> [String: NpmOutdatedRecord] {
        try NpmDecoder.outdated(from: data)
    }
}

/// When an outdated check completed.
///
/// A seam rather than `Date()`, so "checked an hour ago" is testable in
/// milliseconds — the cadence rule in the next slice is written entirely against
/// this.
public protocol NpmClock: Sendable {
    func now() -> Date
}

public struct SystemNpmClock: NpmClock {
    public init() {}
    public func now() -> Date { Date() }
}
