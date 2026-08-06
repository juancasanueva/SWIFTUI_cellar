import Foundation

/// Decides which published release, if any, corresponds to an installed version.
///
/// ## Why normalisation comes first
///
/// A Homebrew version string is not an upstream tag. Homebrew appends its own
/// **revision** suffix when it rebuilds a formula without the upstream version
/// changing (`2.43.0_1`), and records a cask's **build** beside its version
/// (`1.2.3,456`). Upstream published neither of those strings, so comparing them
/// against a tag list would report "no release matches" for a release that
/// plainly exists — and would do it for exactly the packages a user is most
/// likely to be looking at, since a revision bump is what makes a package
/// outdated in the first place.
///
/// ## Why the rule set stops where it does
///
/// Everything below is a tag shape upstream projects actually publish. What is
/// deliberately absent is any *approximation*: no fallback to the newest release,
/// no substring hit, no nearest-version comparison. A miss is an answer. Showing
/// the notes for `v2.44.1` to somebody running `2.44.0` is not a near-enough
/// answer; it is a wrong one, describing changes they have not installed.
///
/// Pure and `nonisolated`: same version, same name, same page, same release,
/// reproducible with no network and no clock.
public enum ReleaseTagMatcher {
    public nonisolated static func match(
        version: String,
        packageName: String,
        in releases: [GitHubRelease]
    ) -> GitHubRelease? {
        let normalized = normalize(version)
        guard normalized.isEmpty == false else { return nil }

        let exact = normalized.lowercased()
        let candidates = Self.candidates(for: normalized, packageName: packageName)

        for release in releases {
            // A draft is not published: it is visible only to people with write
            // access, its tag may not exist yet, and its body is a work in
            // progress. It never matches, not even exactly.
            guard release.isDraft == false else { continue }

            let tag = release.tagName.lowercased()
            guard tag.isEmpty == false else { continue }

            // A prerelease *is* published and can be what the user installed —
            // but only an exact tag reaches it. Admitting it through the
            // `v`-prefix or a name-prefixed candidate would let somebody on a
            // stable version be shown a release candidate's notes.
            if release.isPrerelease {
                if tag == exact { return release }
                continue
            }

            if candidates.contains(tag) { return release }
        }
        return nil
    }

    // MARK: - Normalisation

    /// Strips Homebrew's own suffixes, and nothing else.
    ///
    /// Order matters: the build suffix is separated by `,` and the revision
    /// suffix by `_`, and a rebuilt cask carries both (`1.2.3,456_2`). Cutting at
    /// the first of either leaves the upstream version whatever order they appear
    /// in.
    nonisolated static func normalize(_ version: String) -> String {
        var normalized = version.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [",", "_"] where normalized.contains(separator) {
            normalized = String(normalized.split(separator: separator, maxSplits: 1)[0])
        }
        return normalized
    }

    // MARK: - The candidate table

    /// Every tag string that means "this version", lowercased.
    ///
    /// A `Set` rather than a sequence of comparisons so the answer cannot depend
    /// on the order of the page — exactly one release satisfies the rule set, and
    /// shuffling the list must not change which one comes back.
    private nonisolated static func candidates(
        for version: String,
        packageName: String
    ) -> Set<String> {
        let value = version.lowercased()
        let name = packageName.lowercased()

        var candidates: Set<String> = [value, "v\(value)"]
        // Name-prefixed shapes are keyed to *this* package's name, which is what
        // keeps a monorepo's `bar-2.44.0` from matching `foo`.
        if name.isEmpty == false {
            candidates.formUnion([
                "\(name)-\(value)", "\(name)-v\(value)",
                "\(name)_\(value)", "\(name)_v\(value)"
            ])
        }
        candidates.formUnion(["release-\(value)", "release-v\(value)"])
        return candidates
    }
}
