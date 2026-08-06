import Foundation

/// `SecurityKit` — advisory scanning and artifact integrity.
///
/// This target answers two questions about an installed inventory: *is anything
/// here known to be vulnerable*, and *is anything here unsigned, un-notarized or
/// quarantined*. It answers them without ever running a command, without ever
/// changing a byte on disk, and without ever talking to a host it did not
/// declare at compile time.
///
/// ## Three prohibitions
///
/// These are enforced by `EgressStructureTests`, which scans this directory with
/// comments stripped. They are documented here, where they are enforced, so the
/// next person to add a file reads the rule before breaking it.
///
/// 1. **No subprocess.** Nothing in this target spawns a process. Signature and
///    notarization verdicts come from Security.framework, and quarantine
///    attributes from the `getxattr`/`listxattr` C functions — not from the
///    `spctl`, `codesign` or `xattr` command-line tools. There is no process
///    boundary here to get argument handling wrong at, because there is no
///    process.
///
/// 2. **No write.** Inspection is read-only. No call in this target removes,
///    sets, moves or creates a filesystem entry, so no inspected artifact can
///    change as a side effect of being looked at. The single exception is the
///    advisory cache's own JSON file in `~/Library/Caches/`, which is derived,
///    re-fetchable data rather than anything the user owns; the guard states
///    that exception exhaustively rather than as an allow-list. Visibility never
///    becomes remediation: no public surface of the integrity half accepts a
///    mutating verb.
///
/// 3. **Two constant hosts.** Advisory acquisition reaches exactly two base
///    URLs, both `static let` string constants. No host is built from user
///    input, no URL literal interpolates, and every egress path checks recorded
///    consent before it runs — off is fully off, including scheduled work.
///
/// ## Why this target has no `brew` edge
///
/// `SecurityKit` depends on `Catalog` alone. It needs no `brew` binary, so it
/// declares no path to one. That absence also keeps the strict-SemVer comparator
/// this target owns **structurally unreachable** from the snooze rule in
/// `BrewClient` (`local-package-metadata` LPM5), where an ordering comparison of
/// Homebrew version strings would silently suppress a real update forever. Every
/// composition point between the two lives in the app target, because no target
/// in this package may see both.
public enum SecurityKit {
    /// The advisory cache file's name, used to build its URL beside
    /// `disk-usage-v1.json` in the app target.
    public static let advisoryCacheFileName = "security-advisories-v1.json"
}
