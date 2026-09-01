import Catalog
import Foundation
import Observation

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
    /// Each identity becomes its **own source's** upgrade — a brew one for a
    /// formula or cask, an npm one for a global package — in selection order and
    /// through the one queue (`package-mutation`).
    @discardableResult
    public func submitUpgrades(
        for ids: [PackageID],
        in inventory: InstalledInventory? = nil
    ) -> [ActivityItem] {
        ids.compactMap { id in
            Self.upgrade(naming: id).map { command in
                submit(command, versions: Self.transition(for: id, in: inventory))
            }
        }
    }

    /// The upgrade for one identity, whichever source owns it.
    ///
    /// Erased at the point of construction rather than switched on at every
    /// call site: the two families build different argv from different
    /// validated wrappers, and beyond that the spine treats them identically.
    /// An identity that could not survive argv composition produces `nil`, so a
    /// caller that cannot build one renders the affordance unavailable rather
    /// than failing at spawn time — exactly as it already did for brew.
    static func upgrade(naming id: PackageID) -> AnyBrewMutation? {
        switch id.kind.source {
        case .homebrew:
            MutationCommand.naming(id, MutationCommand.upgrade).map(AnyBrewMutation.init)
        case .npm:
            NpmCommand.naming(id, NpmCommand.upgrade).map(AnyBrewMutation.init)
        }
    }

    /// The removal for one identity, whichever source owns it.
    static func uninstall(naming id: PackageID) -> AnyBrewMutation? {
        switch id.kind.source {
        case .homebrew:
            MutationCommand.naming(id, MutationCommand.uninstall).map(AnyBrewMutation.init)
        case .npm:
            NpmCommand.naming(id, NpmCommand.uninstall).map(AnyBrewMutation.init)
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
    /// Keyed on `BulkSelection.Action`, which is `CaseIterable` with exactly four
    /// cases — so "no bulk reinstall or zap exists, and no bulk snooze" is
    /// enforced by the type rather than by this switch remembering to omit them.
    /// An identity that could not survive argv composition simply produces no
    /// command, which is why this compacts rather than force-unwraps.
    ///
    /// That compaction is also what makes pin and unpin **formula-only for
    /// free**: `MutationCommand.pin` takes a `FormulaID`, a cask cannot construct
    /// one, and so a cask in `ids` produces no command rather than an invalid
    /// one. `BulkSelection.pinnable` filters casks out before they get here, and
    /// this is the second, structural half of the same rule.
    ///
    /// Snooze is absent by construction rather than by omission. It produces no
    /// `MutationCommand` at all, so a fifth case would need a `case snooze: []`
    /// arm here — a silent no-op returning an empty batch, which the type system
    /// could never catch and which would submit nothing while looking like it
    /// had. It travels its own app-side path instead (design HD11).
    ///
    /// Erased rather than `[MutationCommand]` since the npm source landed: the
    /// two verbs both sources own — upgrade and uninstall — expand per package
    /// **by source**, and a return type naming brew's enum could only have
    /// dropped the npm members silently. Pin and unpin are unaffected in either
    /// direction: they are formula-only by construction, so an npm identity
    /// produces no command for the same structural reason a cask does not.
    public func commands(
        for action: BulkSelection.Action,
        over ids: [PackageID]
    ) -> [AnyBrewMutation] {
        ids.compactMap { id in
            switch action {
            case .upgrade: Self.upgrade(naming: id)
            case .uninstall: Self.uninstall(naming: id)
            // `FormulaID(_ id:)` and **not** `.pin(formula: id.name)`: the
            // name-based factory rebuilds the identity as a formula, so a cask's
            // name would silently become `pin --formula iterm2`. The identity
            // initialiser checks the kind and returns `nil` for a cask, which is
            // what makes "a cask never enters a pin set" true here rather than
            // only in the eligibility derivation.
            case .pin: FormulaID(id).map(MutationCommand.pin).map(AnyBrewMutation.init)
            case .unpin: FormulaID(id).map(MutationCommand.unpin).map(AnyBrewMutation.init)
            }
        }
    }

    /// Runs a bulk action, asking first — always.
    ///
    /// Every bulk action asks, not only the destructive ones: one click
    /// covering N operations is agreed on the whole of what it will do before
    /// anything is enqueued (bulk-confirmation ruling 2026-09-01). The
    /// destructive gate `request(_:)` is deliberately not widened — it reads a
    /// command's *nature*, and a lone pin still asks nothing — so the sequence
    /// paths below confirm exactly what they confirmed before.
    ///
    /// Returns `nil` only for an empty batch, keeping the "no request means
    /// nothing left to ask about" shape callers already treat as submitted.
    /// The request carries each package's intended version transition, so the
    /// confirmed path records the same from→to a direct submission records.
    @discardableResult
    public func submitBulk(
        _ action: BulkSelection.Action,
        over ids: [PackageID],
        in inventory: InstalledInventory? = nil
    ) -> ConfirmationRequest? {
        let commands = commands(for: action, over: ids)
        guard let first = commands.first else { return nil }

        // The uninstall batch keeps the lead-disclosure rule (PM1); every
        // other action states what it actually does, never the removal text.
        let request = ConfirmationRequest(
            id: UUID(),
            command: first,
            additional: Array(commands.dropFirst()),
            disclosure: action == .uninstall
                ? commands.leadDisclosure
                : .bulkAction(action, count: commands.count),
            transitions: Self.transitions(for: commands, in: inventory)
        )
        setPendingConfirmation(request)
        return request
    }

    /// Asks before the grouped bare `brew upgrade`.
    ///
    /// Always asks, so the return is not optional — there is no direct path
    /// from this call. The command itself stays non-destructive (product Q2):
    /// the menu-bar popover, which has no sheet host and would latch an
    /// unanswered request on the shared channel, still submits `.upgradeAll`
    /// directly through `submit`.
    @discardableResult
    public func submitUpgradeAll() -> ConfirmationRequest {
        let request = ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(MutationCommand.upgradeAll),
            additional: [],
            disclosure: .upgradeEverything
        )
        setPendingConfirmation(request)
        return request
    }

    /// The intended moves for every package the batch names, out of the
    /// snapshot the caller is already holding — the same derivation the direct
    /// path used, keyed so `confirm` can reunite each command with its own.
    private static func transitions(
        for commands: [AnyBrewMutation],
        in inventory: InstalledInventory?
    ) -> [PackageID: VersionTransition] {
        guard let inventory else { return [:] }
        var moves: [PackageID: VersionTransition] = [:]
        for id in commands.compactMap(\.packageID) {
            if let move = transition(for: id, in: inventory) { moves[id] = move }
        }
        return moves
    }

    /// Submits an ordered sequence of commands as **one** user action, asking
    /// once when any member requires it.
    ///
    /// The same shape as `submitBulk`, and for the same reason: one request
    /// covers the whole sequence, so confirming submits every command it listed
    /// and declining submits none of them — never a partial subset
    /// (package-mutation PM3 :238-243).
    ///
    /// Each member still gets its own queue item, log, copy-command, cancel and
    /// terminal outcome, which is what makes a failed revocation visible instead
    /// of swallowed into the removal that succeeded (TM7 :228-231).
    @discardableResult
    public func submitSequence(_ commands: [some BrewMutating]) -> ConfirmationRequest? {
        if let request = request(commands) { return request }
        for command in commands { submit(command) }
        return nil
    }

    /// The same user action, and the same single confirmation — but each command
    /// after the first is submitted **only once the one before it has settled as
    /// succeeded** (maintainer decision D4, 2026-08-23).
    ///
    /// `submitSequence` above fans everything out at submission time and never
    /// looks back, which is right for N independent packages and wrong for an
    /// action whose second command only means anything if the first one
    /// happened. Untap is the second kind: `brew` refuses to untap a tap that
    /// still owns installed packages, and the revocation behind that refusal
    /// would strip the grant off a tap that is still installed — leaving Force
    /// Untap hidden and no way forward.
    ///
    /// The confirmation shape is deliberately identical: one request covering
    /// the whole sequence, declining submits none of it, never a partial subset
    /// (package-mutation PM3 :238-243). Only the execution differs, and the
    /// request carries `dependsOnLead` so `confirm(_:)` knows which one it
    /// answered.
    ///
    /// A refused lead therefore produces exactly one queue item, carrying brew's
    /// own reason — never a second item for a command that was never run.
    @discardableResult
    public func submitDependentSequence(_ commands: [some BrewMutating]) -> ConfirmationRequest? {
        if let request = request(commands, dependsOnLead: true) { return request }
        submitDependent(commands)
        return nil
    }

    /// Submits the lead now and arms every follower behind it.
    ///
    /// Generic rather than erased, so the concrete command's own
    /// `classify(exit:fault:log:)` still decides its outcome — the same reason
    /// `OperationCenter.run` is generic (design D4). The confirmed path passes
    /// `[AnyBrewMutation]`, which is what it has always submitted.
    @discardableResult
    func submitDependent(_ commands: [some BrewMutating]) -> [ActivityItem] {
        guard let lead = commands.first else { return [] }
        let item = submit(lead)
        arm(item, followedBy: Array(commands.dropFirst()))
        return [item]
    }

    /// Recursive by construction: each follower arms the next one when it
    /// settles, so "in order, each dependent on the one before it" needs no
    /// index and no queue of its own.
    ///
    /// `isSuccess` and nothing weaker. A cancelled, refused, launch-failed or
    /// abandoned lead all mean the same thing here — the command did not happen
    /// — and a follower submitted off any of them would act on a tap that is
    /// still there.
    private func arm(_ item: ActivityItem, followedBy remaining: [some BrewMutating]) {
        guard let next = remaining.first else { return }
        item.onSettle { [weak self] outcome in
            guard let self, outcome.isSuccess else { return }
            self.arm(self.submit(next), followedBy: Array(remaining.dropFirst()))
        }
    }

    // MARK: - Confirmation (design D6, D8)

    /// Asks for confirmation, when this command needs one.
    ///
    /// Returns `nil` for everything that does not — install, reinstall,
    /// upgrade, upgrade-all, pin and unpin — so a caller can treat "no request"
    /// as "submit directly" without restating the rule (product Q2).
    ///
    /// This concrete overload exists for the same reason `submit` has one: a
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
    ///
    /// The disclosure comes from the batch head **through the shared
    /// abstraction**. It used to come from `(first as? TapCommand)?.disclosure
    /// ?? .packageRemoval`, which was total only while every submitted batch was
    /// unerased: a mixed tap+install batch has to be erased to
    /// `[AnyBrewMutation]` before it can be a batch at all, and the downcast
    /// then failed and quietly presented "This removes installed software."
    /// instead of the tap-trust warning (package-mutation PM1, design DD1).
    public func request(_ commands: [some BrewMutating]) -> ConfirmationRequest? {
        request(commands, dependsOnLead: false)
    }

    /// The one implementation. `dependsOnLead` records *how* a yes will be
    /// carried out, and changes nothing about what the sheet shows or about
    /// which batches raise one at all.
    func request(
        _ commands: [some BrewMutating],
        dependsOnLead: Bool
    ) -> ConfirmationRequest? {
        guard let first = commands.first,
              commands.contains(where: \.requiresConfirmation)
        else { return nil }

        let request = ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(first),
            additional: commands.dropFirst().map(AnyBrewMutation.init),
            disclosure: commands.leadDisclosure,
            dependsOnLead: dependsOnLead
        )
        setPendingConfirmation(request)
        return request
    }

    /// Submits every command the confirmation showed, in the order it showed
    /// them. Nothing was enqueued before this point.
    ///
    /// A `dependsOnLead` request submits only its **lead** here, and the rest as
    /// each predecessor succeeds — so the returned items are the ones that
    /// exist, never a promise of ones that may never be submitted. The yes still
    /// covered the whole sequence; what it agreed to is an action, not two
    /// commands running whatever happens.
    @discardableResult
    public func confirm(_ request: ConfirmationRequest) -> [ActivityItem] {
        guard pendingConfirmation == request else { return [] }
        confirmations.consume(request)
        guard request.dependsOnLead else {
            return request.commands.map { command in
                submit(command, versions: command.packageID.flatMap { request.transitions[$0] })
            }
        }
        return submitDependent(request.commands)
    }

    /// Spawns nothing, enqueues nothing, leaves the inventory untouched.
    public func decline(_ request: ConfirmationRequest) {
        guard pendingConfirmation == request else { return }
        confirmations.decline(request)
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
        public let disclosure: ConfirmationDisclosure
        /// Cleanup-only typed evidence. `nil` for every existing command family.
        public let cleanupDisclosure: CleanupConfirmationDisclosure?
        /// Whether confirming submits the whole sequence at once, or the lead
        /// now and each follower as its predecessor succeeds (D4).
        ///
        /// It says nothing about what the sheet shows: the disclosure, the
        /// listed argv and the all-or-nothing rule are identical either way, and
        /// this is read by `confirm(_:)` alone. Defaulted to `false` so every
        /// existing construction — and every shipped test that builds one —
        /// keeps the fan-out it already had.
        public let dependsOnLead: Bool
        /// The version move each named package is expected to make, so a
        /// confirmed batch records the same from→to a direct submission
        /// records. Empty for every batch that derives none — the sheet reads
        /// nothing from it, and `confirm(_:)` alone reunites each command with
        /// its own.
        public let transitions: [PackageID: VersionTransition]

        public init(
            id: UUID,
            command: AnyBrewMutation,
            additional: [AnyBrewMutation],
            disclosure: ConfirmationDisclosure = .packageRemoval,
            cleanupDisclosure: CleanupConfirmationDisclosure? = nil,
            dependsOnLead: Bool = false,
            transitions: [PackageID: VersionTransition] = [:]
        ) {
            self.id = id
            self.command = command
            self.additional = additional
            self.disclosure = disclosure
            self.cleanupDisclosure = cleanupDisclosure
            self.dependsOnLead = dependsOnLead
            self.transitions = transitions
        }

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
        public var warningText: String {
            cleanupDisclosure?.warningText ?? disclosure.warningText
        }

        public var tapIdentity: TapName? {
            switch disclosure {
            case .tapAdd(let tap), .tapTrustGrant(let tap), .forceUntap(let tap, _): tap
            case .packageRemoval, .bulkAction, .upgradeEverything: nil
            }
        }

        public var affectedPackages: [PackageID] {
            guard case .forceUntap(_, let affected) = disclosure else { return [] }
            return affected.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}

/// The one mutable cell behind `OperationCenter.pendingConfirmation`.
///
/// A separate `@Observable` object rather than a stored property on the centre,
/// so the centre can expose the value as a getter with **no setter at all**
/// while still being able to change it from inside. Observation is not lost by
/// the extra hop: reading the computed property reads `pending` here, so a
/// tracker registered on the centre's property is woken by a write to this one
/// (design D6 — VS2).
///
/// Declared beside the confirmation surface it serves rather than in
/// `OperationCenter.swift`, which is already at this package's 400-line bound.
@MainActor
@Observable
final class ConfirmationBox {
    var pending: OperationCenter.ConfirmationRequest?

    struct RecoveryCandidate {
        let request: OperationCenter.ConfirmationRequest
        let token: MutationOperationToken
        let supersessionKey: String
        let isEligible: @MainActor () -> Bool
        let onCancel: @MainActor () -> Void
    }

    private var visibleRecovery: RecoveryCandidate?
    private var backlog: RecoveryCandidate?

    var visibleRecoveryToken: MutationOperationToken? { visibleRecovery?.token }
    var backloggedToken: MutationOperationToken? { backlog?.token }

    init() {}

    func present(_ request: OperationCenter.ConfirmationRequest) {
        pending = request
        visibleRecovery = nil
    }

    func consume(_ request: OperationCenter.ConfirmationRequest) {
        guard pending == request else { return }
        pending = nil
        visibleRecovery = nil
        promoteBacklog()
    }

    func decline(_ request: OperationCenter.ConfirmationRequest) {
        guard pending == request else { return }
        let cancelled = visibleRecovery
        pending = nil
        visibleRecovery = nil
        cancelled?.onCancel()
        promoteBacklog()
    }

    func enqueueRecovery(
        request: OperationCenter.ConfirmationRequest,
        token: MutationOperationToken,
        supersessionKey: String,
        isEligible: @escaping @MainActor () -> Bool,
        onCancel: @escaping @MainActor () -> Void
    ) {
        guard visibleRecovery?.token != token, backlog?.token != token else { return }
        let candidate = RecoveryCandidate(
            request: request,
            token: token,
            supersessionKey: supersessionKey,
            isEligible: isEligible,
            onCancel: onCancel
        )

        guard pending != nil else {
            present(candidate)
            return
        }
        backlog?.onCancel()
        backlog = candidate
    }

    func supersedeRecovery(for key: String) {
        if visibleRecovery?.supersessionKey == key {
            let cancelled = visibleRecovery
            pending = nil
            visibleRecovery = nil
            cancelled?.onCancel()
            promoteBacklog()
        }
        if backlog?.supersessionKey == key {
            let cancelled = backlog
            backlog = nil
            cancelled?.onCancel()
        }
    }

    func cancelRecovery(token: MutationOperationToken) {
        if visibleRecovery?.token == token {
            let cancelled = visibleRecovery
            pending = nil
            visibleRecovery = nil
            cancelled?.onCancel()
            promoteBacklog()
        }
        if backlog?.token == token {
            let cancelled = backlog
            backlog = nil
            cancelled?.onCancel()
        }
    }

    func shutdown() {
        let visible = visibleRecovery
        let queued = backlog
        if visible != nil { pending = nil }
        visibleRecovery = nil
        backlog = nil
        visible?.onCancel()
        queued?.onCancel()
    }

    private func promoteBacklog() {
        guard pending == nil, let candidate = backlog else { return }
        backlog = nil
        present(candidate)
    }

    private func present(_ candidate: RecoveryCandidate) {
        guard candidate.isEligible() else {
            candidate.onCancel()
            return
        }
        pending = candidate.request
        visibleRecovery = candidate
    }
}
