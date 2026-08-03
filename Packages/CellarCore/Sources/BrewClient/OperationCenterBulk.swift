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

    // There is deliberately **no** `submitUpgradesForOutdated(in:)` here.
    //
    // It derived its own outdated-minus-pinned set over the whole inventory
    // while the button beside it counted the dependency-filtered entries — two
    // sets, announced as one. Callers pass `InstalledBrowse.upgradableIDs`
    // instead, which is the single projection the label, the outdated section,
    // the badge and this submission all read, so the pinned exclusion (PM2 — and
    // still no unpin submitted on their behalf) and the snooze exclusion live in
    // the derivation, once (design D8, installed-inventory II14).

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

    // MARK: - The surface a selection is acted on through (PM8, II13)

    /// What `action` would run over `ids`: one invocation per package, in
    /// selection order.
    ///
    /// Keyed on `BulkSelection.Action`, which is `CaseIterable` with exactly two
    /// cases — so "no bulk pin, unpin, reinstall or zap exists" is enforced by
    /// the type rather than by this switch remembering to omit them. An identity
    /// that could not survive argv composition simply produces no command, which
    /// is why this compacts rather than force-unwraps.
    public func commands(
        for action: BulkSelection.Action,
        over ids: [PackageID]
    ) -> [MutationCommand] {
        ids.compactMap { id in
            switch action {
            case .upgrade: MutationCommand.naming(id, MutationCommand.upgrade)
            case .uninstall: MutationCommand.naming(id, MutationCommand.uninstall)
            }
        }
    }

    /// Runs a bulk action, asking first when the action requires it.
    ///
    /// Returns the pending request when one is owed and `nil` when the batch was
    /// submitted directly — the same "no request means already submitted" shape
    /// the single-command path uses, so a caller restates no rule about which
    /// verbs are destructive.
    @discardableResult
    public func submitBulk(
        _ action: BulkSelection.Action,
        over ids: [PackageID],
        in inventory: InstalledInventory? = nil
    ) -> ConfirmationRequest? {
        let commands = commands(for: action, over: ids)
        if let request = request(commands) { return request }
        for command in commands {
            submit(command, versions: Self.transition(for: command.packageID, in: inventory))
        }
        return nil
    }

    // MARK: - Confirmation (design D6, D8)

    /// Asks for confirmation, when this command needs one.
    ///
    /// Returns `nil` for everything that does not — install, reinstall,
    /// upgrade, upgrade-all, pin and unpin — so a caller can treat "no request"
    /// as "submit directly" without restating the rule (product Q2).
    /// The concrete overload, for the same reason `submit` has one: a
    /// leading-dot literal cannot infer a contextual base against a generic
    /// parameter. It forwards to the batch form, which is the only
    /// implementation.
    public func request(_ command: MutationCommand) -> ConfirmationRequest? {
        request([command])
    }

    public func request(_ command: some BrewMutating) -> ConfirmationRequest? {
        request([command])
    }

    /// Asks **once** for a whole batch.
    ///
    /// One request covering N commands rather than N requests: an all-or-nothing
    /// destructive action must be agreed once, on the whole of what it will do.
    /// Confirming submits every command it listed; declining submits none of
    /// them, never a partial subset (package-mutation PM3 sc5–6).
    public func request(_ commands: [some BrewMutating]) -> ConfirmationRequest? {
        guard let first = commands.first,
              commands.contains(where: \.requiresConfirmation)
        else { return nil }

        let request = ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(first),
            additional: commands.dropFirst().map(AnyBrewMutation.init)
        )
        pendingConfirmation = request
        return request
    }

    /// Submits every command the confirmation showed, in the order it showed
    /// them. Nothing was enqueued before this point.
    @discardableResult
    public func confirm(_ request: ConfirmationRequest) -> [ActivityItem] {
        guard pendingConfirmation == request else { return [] }
        pendingConfirmation = nil
        return request.commands.map { submit($0) }
    }

    /// Spawns nothing, enqueues nothing, leaves the inventory untouched.
    public func decline(_ request: ConfirmationRequest) {
        guard pendingConfirmation == request else { return }
        pendingConfirmation = nil
    }

    /// The transition for a command that may name no package at all.
    private static func transition(
        for id: PackageID?,
        in inventory: InstalledInventory?
    ) -> VersionTransition? {
        guard let id else { return nil }
        return transition(for: id, in: inventory)
    }
}

extension OperationCenter {
    /// One or more destructive commands waiting for a single explicit yes.
    ///
    /// It carries the **typed** commands, so confirming submits exactly what was
    /// shown: there is no path from a rendered string back to argv.
    ///
    /// The head is a stored property and the rest is a list, so "a request always
    /// covers at least one command" is a fact about the type rather than a check
    /// somebody has to remember — an empty confirmation cannot be built at all.
    public struct ConfirmationRequest: Identifiable, Sendable, Equatable {
        public let id: UUID
        /// The first command. A single-package confirmation has only this one.
        ///
        /// Erased, for the reason `ActivityItem.command` is: the request is a
        /// stored value the sheet reads, so it cannot be generic. Erasure is
        /// also what keeps this type `Equatable`, which the presentation
        /// binding and its four shipped assertions depend on (design D1).
        public let command: AnyBrewMutation
        /// Everything else the same yes covers, in selection order.
        public let additional: [AnyBrewMutation]

        /// Every command this confirmation will submit, in order.
        public var commands: [AnyBrewMutation] { [command] + additional }

        /// True when one yes covers more than one package.
        public var isBulk: Bool { !additional.isEmpty }

        /// Each exact command that will run, character for character — never a
        /// count and never an elided subset (PM3 sc5).
        public var displayCommands: [String] { commands.map(\.displayCommand) }

        /// The same, for a surface that renders one string: one command per
        /// line, so a three-package uninstall discloses all three.
        public var displayCommand: String { displayCommands.joined(separator: "\n") }
    }
}
