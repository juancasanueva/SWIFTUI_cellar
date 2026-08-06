import Foundation

/// Which version scheme a string turned out to be written in.
///
/// A typed value rather than a description, because this travels into
/// `notComparable` and a user reading "not comparable" deserves to know which
/// kind of version defeated the comparison. It is also why no part of this file
/// needs a text type.
public enum VersionScheme: Sendable, Hashable {
    /// Parsed as SemVer 2.0.0.
    case strictSemVer
    /// A Homebrew packaging revision, `1.2.3_1`. Covered by the scan, not
    /// comparable by this comparator.
    case homebrewRevision
    /// A date, a release letter, an `r`-prefixed revision — anything this
    /// comparator has no ordering for and will not invent one for.
    case other
}

/// The installed side of a comparison.
///
/// One value rather than an optional plus a scheme, so a caller cannot hand over
/// a missing version and a scheme that disagree with each other.
public enum InstalledVersion: Sendable, Hashable {
    case comparable(StrictSemVer)
    case uninterpretable(VersionScheme)
}

/// What an advisory says about a fix.
///
/// Four states, and the first two are the ones that must never merge.
/// `notPublished` is the advisory *stating* that nothing fixes this — RustSec's
/// unmaintained-crate records declare an `introduced` event and no `fixed` event
/// precisely to say so. `unknown` is an advisory that never addressed the
/// question. A user acts differently on each.
public enum DeclaredFix: Sendable, Hashable {
    /// A fixed version that parses as strict SemVer.
    case published(StrictSemVer)
    /// A fixed version the comparator cannot interpret.
    case publishedUninterpretable(VersionScheme)
    /// The advisory declares a range with no fix in it.
    case notPublished
    /// The advisory says nothing about a fix.
    case unknown
}

/// The verdict for one finding.
public enum FixVersionComparison: Sendable, Hashable {
    /// The fix landed at or before the installed version.
    case fixedAtOrBefore
    /// The fix is ahead of the installed version.
    case stillAffected
    /// The advisory declares there is no fix.
    case noFixPublished
    /// The advisory does not say.
    case fixUnknown
    /// A fix is published and the two sides cannot be ordered. **No claim is
    /// made about whether the installed version is affected.**
    case notComparable(scheme: VersionScheme)
}

/// The one place a version ordering happens.
///
/// ## Why nothing in this file is text
///
/// `theComparatorCannotBeCalledWithStrings` asserts that the word `String` does
/// not appear anywhere in this source — not in a signature, not in an overload,
/// not in a raw value, not in a convenience initialiser someone adds later
/// because it seemed harmless.
///
/// That absoluteness is the point. A comparator that accepts two text values can
/// be handed two Homebrew version strings, and comparing those is what
/// `local-package-metadata` forbids: `1.2.3_1` against `1.2.4` has no ordering
/// that is safe to act on, and a wrong answer silently suppresses a real update
/// forever. A function that *cannot* be called with text cannot be misapplied to
/// text, which turns a rule somebody has to remember into a fact the compiler
/// enforces.
///
/// The manifest half of the same guarantee is `PackageGraphTests`: `BrewClient`
/// declares no dependency on this target and cannot reach it transitively. Taken
/// together, the comparison is unreachable from the snooze decision *and* could
/// not be misused if it were reached.
public enum FixVersionComparator {
    /// Orders two parsed versions. Both sides are strict SemVer by type, so
    /// there is nothing here to get wrong.
    ///
    /// "At or before" includes equality on purpose: the release a fix landed in
    /// is fixed, not still affected.
    public static func compare(
        installed: StrictSemVer,
        fixed: StrictSemVer
    ) -> FixVersionComparison {
        installed < fixed ? .stillAffected : .fixedAtOrBefore
    }

    /// The full five-state resolution.
    ///
    /// Every branch that cannot order returns a verdict that says so. None of
    /// them falls through to an ordering, and none of them guesses.
    public static func resolve(
        installed: InstalledVersion,
        fix: DeclaredFix
    ) -> FixVersionComparison {
        switch fix {
        case .notPublished:
            return .noFixPublished
        case .unknown:
            return .fixUnknown
        case .publishedUninterpretable(let scheme):
            return .notComparable(scheme: scheme)
        case .published(let fixed):
            switch installed {
            case .comparable(let installed):
                return compare(installed: installed, fixed: fixed)
            case .uninterpretable(let scheme):
                return .notComparable(scheme: scheme)
            }
        }
    }
}
