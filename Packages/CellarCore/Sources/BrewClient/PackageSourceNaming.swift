import Catalog
import Foundation

/// The executable name a source's commands are spelled with.
///
/// Deliberately declared here rather than beside `PackageSource` in `Catalog`.
/// `Catalog` knows nothing about running processes — that absence is what keeps
/// catalog acquisition free of any `brew` binary — and a property naming an
/// executable is exactly the knowledge that would erode it. `BrewClient` is the
/// target that already composes argv, so the mapping lives where it is used.
///
/// It is display and prefix vocabulary only, which is why the file is named
/// `PackageSourceNaming.swift` and not `…Command.swift`: the shipped structural
/// argv scan globs every top-level `*Command.swift` and requires each match to
/// declare an `arguments` vector it can inspect. This file declares none, so
/// matching that glob would have forced the scan to be weakened for a file that
/// builds no argv at all. No argv vector is built from it:
/// each command family owns its own fixed vector, and the runner is handed an
/// executable URL, never a name to resolve from `PATH`.
extension PackageSource {
    public var commandName: String {
        switch self {
        case .homebrew: "brew"
        case .npm: "npm"
        }
    }

    /// What a sentence shown to a person calls this source.
    ///
    /// Distinct from `commandName` because the two genuinely differ for one of
    /// them: the executable is `brew` and the product is `Homebrew`, and a
    /// message reading "brew exited with status 1" would be a regression in the
    /// shipped copy. npm's are the same string, which is a fact about npm rather
    /// than a reason to collapse the two properties (design D12).
    public var displayName: String {
        switch self {
        case .homebrew: "Homebrew"
        case .npm: "npm"
        }
    }
}
