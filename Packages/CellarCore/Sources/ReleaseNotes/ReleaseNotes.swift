import Foundation

/// `ReleaseNotes` — what changes if I upgrade this package.
///
/// This target answers one question about one package at one version, and it
/// answers it by asking `api.github.com` at most once per explicit user click.
///
/// ## Five rules, enforced rather than described
///
/// These are asserted by `ReleaseNotesEgressStructureTests`, which scans this
/// directory with comments stripped, and by the composition guards in the app's
/// test target. They are documented here, where they are enforced, so the next
/// person to add a file reads the rule before breaking it.
///
/// 1. **Consent is a compile-time gate, not a remembered call.** The one type
///    that owns a `URLSession` takes a `ReleaseNotesGrant`, and the only producer
///    of a grant is `ReleaseNotesConsent.authorise()`, whose initialiser is
///    internal. Egress before a dated grant is a type error first and a failing
///    test second.
///
/// 2. **One click, one request, and no shape that could fan out.** The fetch
///    surface names a single repository. There is no array overload, no
///    `submitBulk`, no `prefetch`, and no `.task` trigger anywhere. The word
///    `[PackageID]` does not appear in this target.
///
/// 3. **Four absences are four values.** Unresolvable repository, a repository
///    that publishes no releases, no release matching this version, and an
///    unavailable fetch — of which rate-limit exhaustion is its own case
///    carrying its reset time. A `403` never renders as "no release notes", and
///    a rate-limit refusal is never written to the cache.
///
/// 4. **The catalog is frozen.** This target reads four *URL* fields off
///    `CatalogPackage` and writes nothing back. `CatalogSnapshot`,
///    `currentSchemaVersion` and the snapshot footprint are untouched.
///
/// 5. **The token is a secret; the grant is a preference.** The optional GitHub
///    personal access token lives in the Keychain under this capability's own
///    service name. This target names no `UserDefaults`, no `@AppStorage`, and
///    no logging API at all.
///
/// ## Why this target has no `SecurityKit` edge
///
/// `ScanConsent.authorise()` throws an `AdvisoryError`, a CVE-scanner type.
/// Importing `SecurityKit` to reuse two structs would couple release notes to
/// advisory scanning and would let one grant be mistaken for the other. The
/// seams are re-declared instead, under a distinct Keychain service name — the
/// same rules, applied twice.
public enum ReleaseNotes {
    /// The cache file's name, used to build its URL beside `disk-usage-v1.json`
    /// and `security-advisories-v1.json` in the app target.
    public static let cacheFileName = "release-notes-v1.json"
}
