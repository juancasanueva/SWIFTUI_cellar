import Foundation
import ReleaseNotes
import Testing

/// A Homebrew version string is **not** an upstream tag, and matching is what
/// closes the gap — deterministically, and never by guessing.
///
/// The rule set is small on purpose. Every candidate below is a shape upstream
/// projects actually publish; there is no fallback to the newest release, no
/// substring hit, and no nearest-version comparison. A miss is an answer, and an
/// answer the user can act on ("this version predates the releases we can see")
/// beats a wrong note about a different version.
@Suite("Release tag matching")
struct ReleaseTagMatcherTests {
    // MARK: - Arrangement

    private func release(
        _ tag: String,
        name: String? = nil,
        isDraft: Bool = false,
        isPrerelease: Bool = false
    ) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: name ?? tag,
            body: "notes for \(tag)",
            isDraft: isDraft,
            isPrerelease: isPrerelease,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            htmlURL: URL(string: "https://github.com/acme/foo/releases/tag/\(tag)")
        )
    }

    // MARK: - The five spec scenarios

    @Test("A v-prefixed tag matches an unprefixed version")
    func aVPrefixedTagMatchesAnUnprefixedVersion() throws {
        let matched = try #require(
            ReleaseTagMatcher.match(
                version: "2.44.0",
                packageName: "foo",
                in: [release("v2.44.0"), release("v2.43.0")]
            )
        )

        #expect(matched.tagName == "v2.44.0")
    }

    @Test("An exact tag matches")
    func anExactTagMatches() throws {
        let matched = try #require(
            ReleaseTagMatcher.match(
                version: "2.44.0",
                packageName: "foo",
                in: [release("2.44.0"), release("2.43.0")]
            )
        )

        #expect(matched.tagName == "2.44.0")
    }

    /// `2.43.0_1` is Homebrew's *revision* suffix: the formula was rebuilt
    /// without the upstream version changing. Upstream never published a
    /// `v2.43.0_1`, so without stripping this reads as "no release matches" for a
    /// release that plainly exists.
    @Test("A formula revision suffix is stripped before matching")
    func aFormulaRevisionSuffixIsStripped() throws {
        let matched = try #require(
            ReleaseTagMatcher.match(
                version: "2.43.0_1",
                packageName: "foo",
                in: [release("v2.43.0"), release("v2.44.0")]
            )
        )

        #expect(matched.tagName == "v2.43.0")
    }

    /// The cask half of the same problem: `1.2.3,456` is version plus build.
    @Test("A cask build suffix is stripped before matching")
    func aCaskBuildSuffixIsStripped() throws {
        let matched = try #require(
            ReleaseTagMatcher.match(
                version: "1.2.3,456",
                packageName: "tool",
                in: [release("1.2.3"), release("1.2.2")]
            )
        )

        #expect(matched.tagName == "1.2.3")
    }

    /// Both suffixes at once, which Homebrew does publish for rebuilt casks.
    @Test("Both suffixes together are stripped")
    func bothSuffixesTogetherAreStripped() throws {
        let matched = try #require(
            ReleaseTagMatcher.match(
                version: "1.2.3,456_2",
                packageName: "tool",
                in: [release("v1.2.3")]
            )
        )

        #expect(matched.tagName == "v1.2.3")
    }

    /// The rule that keeps a miss honest. Returning `v2.44.1` here would be a
    /// note about changes the user has **not** installed, presented as though
    /// they had.
    @Test("A near miss is a miss, not the newest release")
    func aNearMissIsAMissNotTheNewestRelease() {
        let matched = ReleaseTagMatcher.match(
            version: "2.44.0",
            packageName: "foo",
            in: [release("v2.45.0"), release("v2.44.1")]
        )

        #expect(matched == nil, "matching returned \(String(describing: matched?.tagName))")
    }

    @Test("No fallback to the newest release when the list is non-empty and unmatched")
    func noFallbackToTheNewestRelease() {
        let published = [release("v9.9.9"), release("v9.9.8"), release("v0.0.1")]

        #expect(ReleaseTagMatcher.match(version: "3.1.4", packageName: "foo", in: published) == nil)
        // And no substring hit either: `1.2` must not match `v1.2.0`.
        #expect(
            ReleaseTagMatcher.match(version: "9.9", packageName: "foo", in: published) == nil,
            "a substring matched"
        )
    }

    // MARK: - Design T3: the rules the spec carries no scenario for

    /// Named-tag shapes upstream projects publish. The spec requires "at minimum"
    /// exact and `v`-prefixed and leaves the rest to design; these ship because
    /// this test names them, rather than existing as untested generosity.
    @Test(
        "Name-prefixed and release-prefixed tag shapes match",
        arguments: [
            "foo-2.44.0",
            "foo_v2.44.0",
            "foo-v2.44.0",
            "release-2.44.0",
            "release-v2.44.0"
        ]
    )
    func namePrefixedAndReleasePrefixedShapesMatch(tag: String) throws {
        let matched = try #require(
            ReleaseTagMatcher.match(
                version: "2.44.0",
                packageName: "foo",
                in: [release(tag), release("unrelated-1.0.0")]
            ),
            "\(tag) did not match version 2.44.0 of package foo"
        )

        #expect(matched.tagName == tag)
    }

    /// The name-prefixed shapes are keyed to **this** package's name, so
    /// `bar-2.44.0` in a monorepo's release list is not this package's release.
    @Test("A name-prefixed tag for a different package does not match")
    func aNamePrefixedTagForADifferentPackageDoesNotMatch() {
        let matched = ReleaseTagMatcher.match(
            version: "2.44.0",
            packageName: "foo",
            in: [release("bar-2.44.0"), release("baz_v2.44.0")]
        )

        #expect(matched == nil, "a sibling package's tag matched")
    }

    @Test(
        "Comparison is case-insensitive in both directions",
        arguments: [("V2.44.0", "2.44.0"), ("FOO-2.44.0", "2.44.0"), ("v2.44.0", "2.44.0")]
    )
    func comparisonIsCaseInsensitive(tag: String, version: String) throws {
        let matched = try #require(
            ReleaseTagMatcher.match(version: version, packageName: "FoO", in: [release(tag)]),
            "\(tag) did not match \(version) case-insensitively"
        )

        #expect(matched.tagName == tag)
    }

    /// A draft is not published. It is visible only to people with write access
    /// to the repository, its tag may not exist yet, and its body is a work in
    /// progress — so it never matches, not even on an exact tag.
    @Test("A draft release never matches, not even on an exact tag")
    func aDraftReleaseNeverMatches() {
        #expect(
            ReleaseTagMatcher.match(
                version: "2.44.0",
                packageName: "foo",
                in: [release("2.44.0", isDraft: true)]
            ) == nil
        )
        // And the same tag, undrafted, does match — so the refusal above is
        // about the draft flag and not about the tag.
        #expect(
            ReleaseTagMatcher.match(
                version: "2.44.0",
                packageName: "foo",
                in: [release("2.44.0", isDraft: false)]
            ) != nil
        )
    }

    /// A prerelease is published, so it can be what the user actually installed —
    /// but only when the tag matches **exactly**. Reaching a prerelease through a
    /// `v`-prefix or a name-prefixed candidate would mean a user on a stable
    /// version could be shown a release candidate's notes.
    @Test("A prerelease matches only on an exact tag")
    func aPrereleaseMatchesOnlyOnAnExactTag() throws {
        let exact = try #require(
            ReleaseTagMatcher.match(
                version: "0.11.1-pre",
                packageName: "vivid",
                in: [release("0.11.1-pre", isPrerelease: true)]
            )
        )
        #expect(exact.tagName == "0.11.1-pre")

        // Same release, reached through the `v`-prefix candidate: refused.
        #expect(
            ReleaseTagMatcher.match(
                version: "0.11.1-pre",
                packageName: "vivid",
                in: [release("v0.11.1-pre", isPrerelease: true)]
            ) == nil,
            "a prerelease matched through the v-prefix candidate"
        )
        // And through a name-prefixed candidate: refused.
        #expect(
            ReleaseTagMatcher.match(
                version: "0.11.1-pre",
                packageName: "vivid",
                in: [release("vivid-0.11.1-pre", isPrerelease: true)]
            ) == nil,
            "a prerelease matched through a name-prefixed candidate"
        )
    }

    // MARK: - Purity and determinism

    @Test("Matching is reproducible and issues no request")
    func matchingIsReproducibleAndIssuesNoRequest() async throws {
        // Per-instance and tagged, so no concurrently-running suite can add to
        // this count or reset it.
        let network = RecordingNetwork()

        let published = [release("v2.44.0"), release("v2.43.0"), release("v2.42.0")]
        let first = ReleaseTagMatcher.match(version: "2.44.0", packageName: "foo", in: published)
        let second = ReleaseTagMatcher.match(version: "2.44.0", packageName: "foo", in: published)

        #expect(first == second)
        #expect(first?.tagName == "v2.44.0")
        #expect(network.requestCount == 0)

        // The control, so the zero above is a counted zero.
        _ = try? await network.session.data(
            from: URL(string: "https://api.github.com/repos/acme/foo/releases")!
        )
        #expect(network.requestCount == 1, "the recorder did not notice a real request")
    }

    /// Order does not decide the answer: exactly one release satisfies the rule
    /// set, so shuffling the page cannot change which one comes back.
    @Test("The answer does not depend on the order of the page")
    func theAnswerDoesNotDependOnTheOrderOfThePage() {
        let published = [release("v2.42.0"), release("v2.44.0"), release("v2.43.0")]

        for permutation in [published, published.reversed(), published.shuffled()] {
            #expect(
                ReleaseTagMatcher.match(
                    version: "2.44.0", packageName: "foo", in: Array(permutation)
                )?.tagName == "v2.44.0"
            )
        }
    }

    @Test("An empty page and an empty version are both a miss, not a crash")
    func anEmptyPageAndAnEmptyVersionAreBothAMiss() {
        #expect(ReleaseTagMatcher.match(version: "2.44.0", packageName: "foo", in: []) == nil)
        #expect(
            ReleaseTagMatcher.match(
                version: "", packageName: "foo", in: [release("v2.44.0"), release("")]
            ) == nil,
            "an empty version matched something"
        )
    }

    // MARK: - Against a captured page

    /// The rules, run over a real captured response rather than over three
    /// hand-written releases.
    @Test("A captured page matches the version it published and misses one it did not")
    func aCapturedPageMatchesTheVersionItPublished() async throws {
        let releases = try await GitHubReleaseDecoder.decode(
            Fixture.data("GitHub/releases-git-populated.json")
        )

        let matched = try #require(
            ReleaseTagMatcher.match(version: "1.18.0", packageName: "hyperfine", in: releases)
        )
        #expect(matched.tagName == "v1.18.0")
        #expect(matched.body?.isEmpty == false)

        // The revision-suffix rule, over the same captured page.
        #expect(
            ReleaseTagMatcher.match(
                version: "1.18.0_1", packageName: "hyperfine", in: releases
            )?.tagName == "v1.18.0"
        )

        // A version this repository never published.
        #expect(
            ReleaseTagMatcher.match(version: "99.0.0", packageName: "hyperfine", in: releases) == nil
        )
    }
}
