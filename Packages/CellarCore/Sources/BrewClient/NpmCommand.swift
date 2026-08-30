import BrewProcess
import Catalog
import DiskUsage

// MARK: - Threat response: subprocess argument composition, for a second source
//
// This file is the npm half of the property `MutationCommand.swift` establishes
// for brew, and it is established the same way — by construction rather than by
// discipline (design D14, `npm-source`):
//
// 1. **argv, never a string.** `arguments` below is two fixed vectors of literal
//    enum raw values plus one token taken from a validated wrapper. Nothing
//    joins, quotes, interpolates or shells out, which is why the shipped
//    structural scan over every top-level `*Command.swift` covers this file the
//    day it lands rather than the day somebody remembers to widen a list.
// 2. **Names are refused at construction.** `NpmPackageTarget` is failable, and
//    the gate is `MutationName.isSafe` — the *same* one every brew family uses —
//    plus one rule npm needs and brew does not.
// 3. **The version is part of the token, not of the vector.** `name@latest` is
//    one argv element, built once inside the wrapper's initializer. Assembling
//    it where the vector is written would put an interpolation in the one body
//    that must not have one, and splitting it into two elements would name two
//    packages to npm rather than one package at one version.

/// An npm package identity, proven safe to put in argv.
///
/// The sibling of `PackageTarget`, and deliberately a separate type rather than
/// a widening of it: `PackageTarget`'s whole job is to refuse anything that is
/// not Homebrew's, and a type that admitted both would have no answer to "which
/// executable is this for?" (design D3, D14).
public struct NpmPackageTarget: Sendable, Hashable {
    public let id: PackageID

    /// The upgrade token, built once, here.
    ///
    /// Stored rather than computed at the vector so there is exactly one place
    /// a version suffix is ever attached to a name — and so the argv body stays
    /// free of the interpolation the structural scan forbids.
    public let latestSpec: String

    public var name: String { id.name }

    /// Fails for an identity of any other source, for a name npm or the shell
    /// could read as something other than a package, and for a name carrying a
    /// version.
    public init?(_ id: PackageID) {
        guard id.kind == .npm,
              MutationName.isSafe(id.name),
              Self.isScopedCorrectly(id.name)
        else { return nil }
        self.id = id
        latestSpec = id.name + Self.latestSuffix
    }

    public init?(name: String) {
        self.init(PackageID(kind: .npm, name: name))
    }

    /// What "the latest published version" is spelled as in an npm spec token.
    static let latestSuffix = "@latest"

    /// npm's one naming rule that brew has no counterpart for: `@` may appear
    /// **only** as the first character, where it opens a scope.
    ///
    /// The rule exists to keep a version out of the name. `typescript@5` is a
    /// perfectly valid npm *spec* and an invalid *identity*: accepting it would
    /// let a hostile or merely surprising `ls -g` payload pin an upgrade to a
    /// version Cellar never offered, because `install -g typescript@5@latest` is
    /// not what any row on screen said would happen.
    private static func isScopedCorrectly(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        let remainder = first == "@" ? name.dropFirst() : name[...]
        return remainder.contains("@") == false
    }
}

/// The two npm mutations Cellar can issue.
///
/// Exactly two, and no grouped form: npm has no `upgrade everything` verb that
/// respects the versions the rows showed, so updates apply per package and the
/// selection fans out at the call site exactly as brew's does (decision 2).
public enum NpmCommand: Sendable, Equatable {
    case upgrade(NpmPackageTarget)
    case uninstall(NpmPackageTarget)

    /// The validated package this command acts on. Both cases name one, which
    /// is why this is not optional the way `MutationCommand.packageID` is.
    public var target: NpmPackageTarget {
        switch self {
        case .upgrade(let target), .uninstall(let target): target
        }
    }

    // MARK: - Failable construction

    public static func upgrade(package name: String) -> NpmCommand? {
        NpmPackageTarget(name: name).map { .upgrade($0) }
    }

    public static func uninstall(package name: String) -> NpmCommand? {
        NpmPackageTarget(name: name).map { .uninstall($0) }
    }

    /// The safe way to build a command for an npm identity the UI already holds.
    ///
    /// Named after neither verb for the reason `MutationCommand.naming` is: an
    /// overload sharing a case's name would silently recurse.
    public static func naming(
        _ id: PackageID,
        _ build: (NpmPackageTarget) -> NpmCommand
    ) -> NpmCommand? {
        NpmPackageTarget(id).map(build)
    }

    // MARK: - Vector pieces

    /// Spelled as cases rather than literals so a typo is a compile error and
    /// the set of npm verbs Cellar can issue is enumerable by reading.
    ///
    /// `install` rather than `update`: npm's `update -g` honours the installed
    /// semver range and will not cross a major, so it cannot reach the version
    /// the row is offering. `install -g name@latest` can, and the row and the
    /// command therefore agree (decision 2).
    private enum Verb: String {
        case install
        case uninstall
    }

    private enum Flag: String {
        case global = "-g"
    }
}

extension NpmCommand: BrewMutating {
    /// The argv vector, excluding the `npm` executable itself.
    public var arguments: [String] {
        switch self {
        case .upgrade(let target):
            [Verb.install.rawValue, Flag.global.rawValue, target.latestSpec]
        case .uninstall(let target):
            [Verb.uninstall.rawValue, Flag.global.rawValue, target.name]
        }
    }

    /// Namespaced, so a durable row can never be mistaken for a brew one and
    /// the bare terms `upgrade` and `uninstall` still find it
    /// (`installation-history`).
    public var verb: String {
        switch self {
        case .upgrade: "npmUpgrade"
        case .uninstall: "npmUninstall"
        }
    }

    public var packageID: PackageID? { target.id }

    /// Exactly `uninstall`, on the same rule brew's families follow: the
    /// destructive one is agreed first and the reversible one is not.
    public var requiresConfirmation: Bool {
        switch self {
        case .uninstall: true
        case .upgrade: false
        }
    }

    /// The npm inventory and the disk measurement, and **no brew domain**. A
    /// brew re-snapshot could not observe an npm change, and paying for one
    /// would be 1.27 s and 663 KB spent on a guaranteed no-op (design D11).
    /// The disk domain spawns nothing: it only re-measures directories, and
    /// both npm mutations rewrite one of them.
    public var invalidates: InvalidationScope { [.npmInventory, .diskUsage] }

    /// Both cases rewrite the global prefix's `lib/node_modules` — `install -g`
    /// replaces a package's tree in place, `uninstall -g` removes it — so both
    /// stale the npm area and neither touches a Homebrew root.
    public var diskAreas: Set<DiskArea> {
        switch self {
        case .upgrade, .uninstall: [.npm]
        }
    }

    public var source: PackageSource { .npm }

    /// npm's own signatures, and only npm's.
    ///
    /// Ordered exactly as the shared classifier is, and for the same reason: the
    /// cheap structural facts — a fault, a cancellation, a zero exit — are all
    /// decided before a single byte of subprocess output is examined, so no
    /// prose a package prints can turn a success into a failure.
    ///
    /// What is deliberately **absent** is brew's vocabulary. Homebrew's lock,
    /// sudo-prompt and untrusted-tap phrases classify nothing here: an npm
    /// package that happened to echo "has already locked" must not make Cellar
    /// say Homebrew is busy, and one echoing an untrusted-tap refusal must not
    /// offer a Trust button for a tap npm has never heard of (`npm-source`).
    ///
    /// Confined to the last `MutationOutcome.tailLength` **stderr** lines: npm
    /// writes its diagnostics there, so a package echoing prose on stdout cannot
    /// change what the user is told, and a multi-megabyte log costs a bounded
    /// scan.
    public func classify(
        exit: BrewExit,
        fault: BrewProcessError?,
        log: [LogLine]
    ) -> MutationOutcome {
        if let fault {
            switch fault {
            case .cancelledUnresponsive(let grace): return .abandoned(after: grace)
            case .executableUnavailable, .launchFailed: return .launchFailed
            }
        }
        if exit.reason == .unknownOperation { return .launchFailed }
        if exit.isCancelled { return .cancelled }
        if exit.isSuccess { return .succeeded }

        let tail = log
            .filter { $0.stream == .stderr }
            .suffix(MutationOutcome.tailLength)
            .map(\.text)

        if tail.contains(where: Signature.isPrivilege) { return .needsPrivileges }
        if tail.contains(where: Signature.isNetwork) { return .networkUnavailable }

        return .failed(status: exit.status)
    }

    /// The npm error codes this family reads, and the only bytes of the payload
    /// it ever looks at. Nothing is captured, extracted or echoed from them.
    ///
    /// Codes rather than sentences: npm's prose is localised and reworded
    /// between majors, while `npm error code EACCES` is the stable machine-facing
    /// half of the same line (live probe, npm 10.9.2).
    private enum Signature {
        /// Permission failures. `EACCES` is the ordinary "your global prefix is
        /// root-owned" case; `EPERM` is its sibling on an unlink or a rename.
        static let privilege = ["EACCES", "EPERM"]

        /// The registry could not be reached. Shared, verbatim, with the read
        /// path's `NpmPayload.networkCodes` — the same four codes decide the
        /// same fact whether npm was listing or installing.
        static let network = NpmPayload.networkCodes

        static func isPrivilege(_ line: String) -> Bool {
            privilege.contains { line.contains($0) }
        }

        static func isNetwork(_ line: String) -> Bool {
            network.contains { line.contains($0) }
        }
    }
}
