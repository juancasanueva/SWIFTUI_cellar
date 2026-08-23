import Catalog
import Foundation

/// A selection, expanded into the commands that will run.
///
/// It **cannot fail** and **cannot emit free text**. Both follow from its input:
/// a `BrewfileEntry` already holds a constructed `TapName`, `FormulaID` or
/// `CaskID`, so there is no name left to validate and no string left to
/// compose. The whole of PM9's file-sourced clause is discharged upstream, at
/// parse time, by the shape of the entry type (`brewfile-management` BF7,
/// `package-mutation` PM9).
///
/// Nothing new enters the spine here. Every command is one of the two **shipped**
/// families — `TapCommand.addTap` or `MutationCommand.install` — so this
/// capability adds no mutating command family, no seventh case of
/// `MutationCommand`, and no invalidation domain.
///
/// **Taps lead, always.** That is load-bearing twice: a package from a newly
/// added tap must not be attempted before its tap exists, and the shared
/// confirmation gate derives a batch's disclosure from `commands.first`
/// (`OperationCenterBulk.request(_:)`), so a mixed batch presents the tapAdd
/// warning only when a tap is at the head of it (design DD1). Reordering this
/// would silently downgrade a security warning, not merely reorder work.
public struct BrewfilePlan: Sendable, Equatable {
    /// Tap adds, in file order.
    public let taps: [TapCommand]
    /// Installs, in file order.
    public let installs: [MutationCommand]

    public init(selecting entries: [BrewfileEntry]) {
        var taps: [TapCommand] = []
        var installs: [MutationCommand] = []

        for entry in entries {
            switch entry.kind {
            case .tap(let name, _):
                taps.append(.addTap(name))
            case .formula, .cask:
                // The entry's own projection, not a string this type composed
                // (**D3**). An entry whose bare token cannot construct produces
                // no command, and the import must not present it as applied.
                if let target = entry.installTarget { installs.append(.install(target)) }
            }
        }

        self.taps = taps
        self.installs = installs
    }

    /// The batch, erased, in submission order.
    ///
    /// Erased because a mixed batch has no single concrete type, and because
    /// `OperationCenter.request(_:)` reads every projection it needs — including
    /// the disclosure — through the shared abstraction (design DD1).
    public var commands: [AnyBrewMutation] {
        taps.map(AnyBrewMutation.init) + installs.map(AnyBrewMutation.init)
    }

    public var isEmpty: Bool { taps.isEmpty && installs.isEmpty }

    /// Exactly what will run, one command per line, for a surface that wants to
    /// show the batch before asking about it.
    public var displayCommands: [String] { commands.map(\.displayCommand) }
}
