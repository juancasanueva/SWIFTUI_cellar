//
//  AppVersion.swift
//  Updates
//

import Foundation

/// Why a version string could not be read.
///
/// Named cases rather than a `Bool` or a `nil`: `1.0` and `1.0.x` are different
/// defects with different fixes, and a caller that has to explain itself needs
/// to know which one it hit. Nothing here falls back to a fabricated version —
/// a version that compares is a version that can offer or refuse an update for
/// the wrong reason.
public enum AppVersionParseFailure: Error, Sendable, Hashable {
    /// The string was empty or was only whitespace.
    case empty
    /// The marketing version did not have exactly three dot-separated components.
    case wrongComponentCount(String)
    /// A component that had to be a number was not one. Carries the component.
    case nonNumericComponent(String)
    /// The build number was present but was not a number. Carries the raw value.
    case nonNumericBuildNumber(String)
}

/// The version pair a copy of Cellar was built with, and how two of them compare.
///
/// A value type with no side effects, so ordering is a pure function of its
/// inputs. Comparison runs marketing version first, then prerelease **below**
/// its own release, then build number — which is what makes a rebuild of the
/// same marketing version newer than its predecessor without letting a high
/// build number promote an older marketing version.
public struct AppVersion: Sendable, Hashable, Comparable {
    /// A marketing version's `-rc.1` suffix, split into the parts that order.
    public struct Prerelease: Sendable, Hashable, Comparable {
        public let identifier: String
        public let ordinal: Int?

        public init(identifier: String, ordinal: Int?) {
            self.identifier = identifier
            self.ordinal = ordinal
        }

        public static func < (lhs: Prerelease, rhs: Prerelease) -> Bool {
            if lhs.identifier != rhs.identifier { return lhs.identifier < rhs.identifier }
            return isAscending(lhs.ordinal, rhs.ordinal)
        }
    }

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: Prerelease?
    public let buildNumber: Int?

    /// Parses a marketing version, and optionally the build number beside it.
    ///
    /// The build number is a separate parameter rather than part of the string
    /// because that is how a bundle stores it: two independent keys, either of
    /// which can be absent or wrong on its own.
    public init(parsing shortVersionString: String, buildNumber: String? = nil) throws(AppVersionParseFailure) {
        let trimmed = shortVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }

        let (base, suffix) = Self.split(trimmed)
        let components = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3 else { throw .wrongComponentCount(shortVersionString) }

        var numbers: [Int] = []
        for component in components {
            guard let number = Int(component) else { throw .nonNumericComponent(component) }
            numbers.append(number)
        }

        self.major = numbers[0]
        self.minor = numbers[1]
        self.patch = numbers[2]
        self.prerelease = try Self.prerelease(from: suffix)
        self.buildNumber = try Self.build(from: buildNumber)
    }

    /// Builds the pair from the two raw strings a bundle's information dictionary
    /// supplies, and answers `nil` when either is absent or unreadable.
    ///
    /// Silence is the only safe answer to "this bundle does not say what it is".
    /// Substituting a placeholder would report a version the app was not built
    /// with, which is exactly what the honest-version requirement forbids.
    public init?(shortVersionString: String?, buildNumber: String?) {
        guard let shortVersionString, let buildNumber else { return nil }
        guard let parsed = try? AppVersion(parsing: shortVersionString, buildNumber: buildNumber) else { return nil }
        self = parsed
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let left = (lhs.major, lhs.minor, lhs.patch)
        let right = (rhs.major, rhs.minor, rhs.patch)
        if left != right { return left < right }

        switch (lhs.prerelease, rhs.prerelease) {
        case (.some, .none):
            // A prerelease sorts below its own release.
            return true
        case (.none, .some):
            return false
        case let (.some(left), .some(right)) where left != right:
            return left < right
        default:
            return isAscending(lhs.buildNumber, rhs.buildNumber)
        }
    }

    /// Splits `1.0.0-rc.1` into its base and its suffix at the first hyphen.
    private static func split(_ version: String) -> (base: String, suffix: String?) {
        guard let hyphen = version.firstIndex(of: "-") else { return (version, nil) }
        return (String(version[version.startIndex..<hyphen]), String(version[version.index(after: hyphen)...]))
    }

    /// Reads `rc.1` as the identifier `rc` and the ordinal `1`.
    ///
    /// A suffix with no ordinal (`beta`) is legal and orders below any ordinal of
    /// the same identifier. A suffix whose ordinal is present but not a number is
    /// a defect, not a version with a strange name.
    private static func prerelease(from suffix: String?) throws(AppVersionParseFailure) -> Prerelease? {
        guard let suffix else { return nil }
        guard !suffix.isEmpty else { throw .nonNumericComponent(suffix) }

        let parts = suffix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return Prerelease(identifier: parts[0], ordinal: nil) }
        guard let ordinal = Int(parts[1]) else { throw .nonNumericComponent(parts[1]) }
        return Prerelease(identifier: parts[0], ordinal: ordinal)
    }

    private static func build(from raw: String?) throws(AppVersionParseFailure) -> Int? {
        guard let raw else { return nil }
        guard let number = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw .nonNumericBuildNumber(raw)
        }
        return number
    }
}

/// Orders two optional numbers with "absent" below "present".
///
/// Shared by the build number and the prerelease ordinal, which order the same
/// way for the same reason: a value that was never recorded cannot be newer than
/// one that was.
private func isAscending(_ lhs: Int?, _ rhs: Int?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .some): true
    case let (.some(left), .some(right)): left < right
    default: false
    }
}
