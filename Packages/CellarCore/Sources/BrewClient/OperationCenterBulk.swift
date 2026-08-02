import Catalog
import Foundation

/// Bulk submission, and the confirmation gate in front of it (design D6, D8 —
/// package-mutation PM3, PM8).
///
/// Split out of `OperationCenter.swift` rather than added to it: the centre's
/// core — attachment, one operation start to finish, cancel — is one story, and
/// "what a selection expands to, and what has to be agreed before it does" is
/// another. Keeping both in one declaration would have put the file past the
/// 400-line mark this package holds itself to (design D12).
extension OperationCenter {

    // MARK: - Fan-out (PM8)

    /// Expands a selection into one ordinary upgrade per package.
    ///
    /// There is no `upgradeSelected` command: the fan-out happens here, at the
    /// call site, so every selected package gets its own queue item, log,
    /// copy-command, cancel and terminal outcome — and a mid-batch failure
    /// attributes to exactly one package (design D1, user ruling 2026-08-02).
    ///
    /// `inventory` is read only to derive each package's intended version
    /// transition, out of the snapshot the caller is **already holding**.
    /// Nothing is re-snapshotted and nothing is diffed either side of the
    /// operation (design D7).
    @discardableResult
    public func submitUpgrades(
        for ids: [PackageID],
        in inventory: InstalledInventory? = nil
    ) -> [ActivityItem] {
        ids.compactMap { id in
            MutationCommand.naming(id, MutationCommand.upgrade).map { command in
                submit(command, versions: Self.transition(for: id, in: inventory))
            }
        }
    }

    /// The same, over everything the inventory reports as outdated.
    ///
    /// The outdated set comes from `InstalledInventory` rather than being
    /// re-derived, so the exclusion of self-updating casks agrees with the
    /// inventory's own derivation (M2-1 II4/II5). Pinned packages are excluded
    /// too and **no unpin is submitted on their behalf**: brew's own defaults
    /// skip them, and defeating that would upgrade something the user
    /// explicitly held back (package-mutation PM2).
    @discardableResult
    public func submitUpgradesForOutdated(in inventory: InstalledInventory) -> [ActivityItem] {
        submitUpgrades(
            for: inventory.packages
                .filter { $0.isOutdated && !$0.isPinned }
                .map(\.id),
            in: inventory
        )
    }

    /// The move an upgrade of `id` is expected to make: what is installed now,
    /// toward what brew is currently offering.
    ///
    /// `nil` whenever either end is unknown — an unlisted package, or a record
    /// with no published version — because half a transition reads as data loss
    /// rather than as absence.
    static func transition(
        for id: PackageID,
        in inventory: InstalledInventory?
    ) -> VersionTransition? {
        guard let package = inventory?.package(id) else { return nil }
        return VersionTransition(from: package.installedVersion, to: package.catalogVersion)
    }

    // MARK: - Confirmation (design D6)

    /// A destructive command waiting for an explicit yes.
    ///
    /// It carries the **typed** command, so confirming submits exactly what was
    /// shown: there is no path from the rendered string back to argv.
    public struct ConfirmationRequest: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let command: MutationCommand

        /// The exact command that will run, character for character.
        public var displayCommand: String { command.displayCommand }
    }

    /// Asks for confirmation, when this command needs one.
    ///
    /// Returns `nil` for everything that does not — install, reinstall,
    /// upgrade, upgrade-all, pin and unpin — so a caller can treat "no request"
    /// as "submit directly" without restating the rule (product Q2).
    public func request(_ command: MutationCommand) -> ConfirmationRequest? {
        guard command.requiresConfirmation else { return nil }
        let request = ConfirmationRequest(id: UUID(), command: command)
        pendingConfirmation = request
        return request
    }

    /// Submits the confirmed command. Nothing was enqueued before this point.
    @discardableResult
    public func confirm(_ request: ConfirmationRequest) -> ActivityItem? {
        guard pendingConfirmation == request else { return nil }
        pendingConfirmation = nil
        return submit(request.command)
    }

    /// Spawns nothing, enqueues nothing, leaves the inventory untouched.
    public func decline(_ request: ConfirmationRequest) {
        guard pendingConfirmation == request else { return }
        pendingConfirmation = nil
    }
}
