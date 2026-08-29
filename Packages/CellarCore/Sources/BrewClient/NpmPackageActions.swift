import Foundation

extension NpmCommand {
    /// The verbs one installed npm package is offered, in menu order.
    ///
    /// Derived once, here, so the row's menu and the detail pane's Actions row
    /// cannot disagree about what an npm package may do — the same discipline
    /// `MutationMenu` keeps for brew by reading `MutationCommand` alone.
    ///
    /// Empty rather than "disabled" for anything that cannot act: a brew entry,
    /// an entry that is not installed, or a name that fails `NpmPackageTarget`'s
    /// gate. An unvalidated command is not representable, so there is nothing
    /// to disable (design D9, PM9).
    ///
    /// Upgrade appears only while the entry is outdated — the row's own
    /// `isOutdated`, which for npm is `current != latest` from a fresh
    /// `outdated -g` (`npm-source`). Uninstall is always offered.
    public static func available(for entry: PackageEntry) -> [NpmCommand] {
        guard let installed = entry.installed,
              let target = NpmPackageTarget(entry.id)
        else { return [] }
        var commands: [NpmCommand] = []
        if installed.isOutdated { commands.append(.upgrade(target)) }
        commands.append(.uninstall(target))
        return commands
    }

    /// The button title for this verb. The trailing ellipsis marks the one
    /// that confirms, exactly as the brew menu spells it.
    public var title: String {
        switch self {
        case .upgrade: "Upgrade"
        case .uninstall: "Uninstall…"
        }
    }
}
