import Foundation

/// The lexical decomposition of a Homebrew version string.
///
/// Homebrew appends `_<digits>` when it rebuilds a formula without the upstream
/// version changing — `1.2.3_1` is upstream `1.2.3`, packaging revision 1.
/// Advisory databases have never heard of that suffix, so it is removed before a
/// version is put on the wire.
///
/// ## This file contains no comparison, by assertion
///
/// `theSplitFileContainsNoComparisonOperator` scans this file, with comments
/// stripped, and fails on `<`, `>`, `compare(`, `.numeric`, `Comparable`,
/// `sorted`, `precedes`, `isNewer` or `isOlder`. That is not stylistic.
/// `local-package-metadata` forbids an ordering comparison of Homebrew version
/// strings anywhere near the snooze decision, because one would silently
/// suppress a real update forever — and this is the single file in this target
/// that handles a raw Homebrew version string, so it is the one place an
/// ordering could be added and look like it belonged.
///
/// The consequence for the implementation below is real: it finds a separator
/// and slices, using `prefix(upTo:)` rather than a range operator, and decides
/// "is this a digit" per character rather than against a bound.
///
/// ## The failure direction is deliberate
///
/// Querying upstream `1.2.3` for an installed `1.2.3_1` can surface an advisory
/// the Homebrew revision already patched. That is a **visible false positive**,
/// which is the direction this codebase has repeatedly chosen over a silent
/// false negative: a user can dismiss a finding they can see, and can do nothing
/// at all about one that was never shown.
public enum HomebrewRevision {
    /// Splits a trailing `_<digits>` packaging revision off a version string.
    ///
    /// Returns the input unchanged with a `nil` revision when there is no such
    /// suffix — including for `1.2.3_beta` (not digits), `1.2_3.4` (the tail is
    /// not all digits), `1.2.3_` (empty tail) and `_1` (nothing in front).
    ///
    /// `revision` distinguishes `0` from `nil`. Homebrew writes revision zero
    /// explicitly, so `1.0_0` and `1.0` are different installed strings that
    /// share an upstream, and collapsing the two answers loses the only thing
    /// that tells them apart.
    public static func split(_ version: String) -> (upstream: String, revision: Int?) {
        let unchanged = (upstream: version, revision: Int?.none)

        guard let separator = version.lastIndex(of: "_") else { return unchanged }

        let tail = version[version.index(after: separator)...]
        guard tail.isEmpty == false, tail.allSatisfy(isASCIIDigit) else { return unchanged }
        guard let revision = Int(tail) else { return unchanged }

        let upstream = String(version.prefix(upTo: separator))
        guard upstream.isEmpty == false else { return unchanged }

        return (upstream: upstream, revision: revision)
    }

    /// Decided per character rather than against a bound, because a bound is a
    /// comparison and this file may not contain one.
    ///
    /// `Character.isNumber` alone would also accept non-ASCII digits, which
    /// `Int(_:)` then rejects — two rules disagreeing about the same string is
    /// how a `nil` revision turns into a crash somewhere else.
    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
