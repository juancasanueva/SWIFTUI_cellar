//
//  CaskAppVersion.swift
//  cellar
//

import Foundation

/// Whether a self-updating app is really behind, judged by the version the
/// app on disk reports rather than the one Homebrew recorded at install.
///
/// Brew's record goes stale the moment the app updates itself — Ghostty's
/// record can say 1.2.3 while the bundle is already 1.4.0 — so comparing the
/// record with the catalog lists apps that are current. Homebrew's own
/// `auto_updates_bundle_outdated?` reads the bundle for the same reason; this
/// is its rule in the shape Cellar needs.
nonisolated enum CaskAppVersion {
    /// `true` when the app is behind `catalogVersion`, `false` when it is at
    /// or past it, and `nil` when the app reports no usable version.
    ///
    /// The short version (`CFBundleShortVersionString`) decides, against the
    /// catalog's first comma-separated part. The bundle version decides only
    /// when there is no short one: it is often a bare build number, and a
    /// build number of 32913 is not "newer" than 5.2.7.
    static func isBehind(shortVersion: String?, bundleVersion: String?, catalogVersion: String) -> Bool? {
        let catalogShort = catalogVersion.split(separator: ",").first.map(String.init) ?? catalogVersion
        if let short = usable(shortVersion) {
            return compare(short, catalogShort) < 0
        }
        if let bundle = usable(bundleVersion) {
            return compare(bundle, catalogVersion) < 0
        }
        return nil
    }

    /// The app's reported versions, read from its `Info.plist`.
    static func versions(ofAppAt appURL: URL) -> (short: String?, bundle: String?) {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return (nil, nil) }
        return (
            info["CFBundleShortVersionString"] as? String,
            info["CFBundleVersion"] as? String
        )
    }

    /// Brew's `AUTO_UPDATES_BAD_BUNDLE_VERSIONS`: placeholders that say nothing.
    private static func usable(_ version: String?) -> String? {
        guard let version = version?.trimmingCharacters(in: .whitespaces),
              !version.isEmpty, !["0", "0.0"].contains(version)
        else { return nil }
        return version
    }

    /// Component-wise, numeric where both sides are numbers. Compared only as
    /// far as the shorter side goes, so "5.2.7" against "5.2.7.32913" is equal:
    /// the catalog often appends a build the app does not repeat.
    private static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = components(lhs)
        let right = components(rhs)
        for (a, b) in zip(left, right) where a != b {
            if let x = Int(a), let y = Int(b) { return x < y ? -1 : 1 }
            return a < b ? -1 : 1
        }
        return 0
    }

    private static func components(_ version: String) -> [String] {
        version
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
