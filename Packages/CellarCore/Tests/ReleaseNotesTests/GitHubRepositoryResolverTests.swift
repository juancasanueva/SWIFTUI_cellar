import Catalog
import Foundation
import ReleaseNotes
import Testing

/// Resolution is a **union** of four published URLs, and the precedence order is
/// a tie-break only.
///
/// The distinction is the whole requirement. Probe U5 measured, over a real
/// installed inventory, that `homepage` resolves 24.5% of formulae and 9.1% of
/// casks while `urls.stable` resolves 54.7% — and that where more than one field
/// yielded a repository, the fields **disagreed zero times**. So precedence buys
/// coverage and never correctness: a package resolvable only through
/// `urls.stable` must still resolve, and a field that yields nothing must never
/// stop a later one from answering.
@Suite("GitHub repository resolution")
struct GitHubRepositoryResolverTests {
    // MARK: - The union rule

    /// U5's headline case, and the one a homepage-first precedence gets wrong:
    /// the homepage is a real project page on a host that is not GitHub, and the
    /// only GitHub URL is the source tarball.
    @Test("A package resolvable only via urls.stable still resolves, credited to it")
    func aPackageResolvableOnlyViaStableUrlStillResolves() throws {
        let resolved = try #require(
            GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: "https://gnu.org/software/foo",
                    headURL: nil,
                    stableURL: "https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz",
                    caskDownloadURL: nil
                )
            )
        )

        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "foo"))
        #expect(resolved.source == .stableURL)
        #expect(resolved.agreeingSourceCount == 1)
    }

    @Test("A cask resolves from its download URL")
    func aCaskResolvesFromItsDownloadUrl() throws {
        let resolved = try #require(
            GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: "https://example.com",
                    headURL: nil,
                    stableURL: nil,
                    caskDownloadURL: "https://github.com/acme/tool/releases/download/v3.0/tool.dmg"
                )
            )
        )

        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "tool"))
        #expect(resolved.source == .caskDownloadURL)
    }

    /// Each of the four **alone**, so no field is load-bearing only because
    /// another happens to be present in every other test.
    @Test(
        "Each candidate field resolves on its own",
        arguments: [
            (RepositorySource.homepage, "https://github.com/acme/foo"),
            (RepositorySource.headURL, "https://github.com/acme/foo.git"),
            (RepositorySource.stableURL, "https://github.com/acme/foo/archive/refs/tags/v1.tar.gz"),
            (RepositorySource.caskDownloadURL, "https://github.com/acme/foo/releases/download/v1/f.dmg")
        ]
    )
    func eachCandidateFieldResolvesOnItsOwn(source: RepositorySource, url: String) throws {
        var candidates = RepositoryCandidates(
            homepage: nil, headURL: nil, stableURL: nil, caskDownloadURL: nil
        )
        switch source {
        case .homepage: candidates = RepositoryCandidates(
            homepage: url, headURL: nil, stableURL: nil, caskDownloadURL: nil
        )
        case .headURL: candidates = RepositoryCandidates(
            homepage: nil, headURL: url, stableURL: nil, caskDownloadURL: nil
        )
        case .stableURL: candidates = RepositoryCandidates(
            homepage: nil, headURL: nil, stableURL: url, caskDownloadURL: nil
        )
        case .caskDownloadURL: candidates = RepositoryCandidates(
            homepage: nil, headURL: nil, stableURL: nil, caskDownloadURL: url
        )
        }

        let resolved = try #require(GitHubRepositoryResolver.resolve(candidates))

        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "foo"))
        #expect(resolved.source == source)
        #expect(resolved.agreeingSourceCount == 1)
    }

    // MARK: - The tie-break

    @Test("With all four agreeing, the tie-break credits homepage and counts all four")
    func withAllFourAgreeingTheTieBreakCreditsHomepage() throws {
        let resolved = try #require(
            GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: "https://github.com/acme/foo",
                    headURL: "https://github.com/acme/foo.git",
                    stableURL: "https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz",
                    caskDownloadURL: "https://github.com/acme/foo/releases/download/v1.2.0/foo.dmg"
                )
            )
        )

        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "foo"))
        #expect(resolved.source == .homepage)
        #expect(resolved.agreeingSourceCount == 4)
    }

    /// The half that says the order is a **tie-break** and not a precedence:
    /// removing the winner does not remove the answer, it only moves the credit.
    @Test("Removing homepage alone still resolves, credited to headURL")
    func removingHomepageAloneStillResolves() throws {
        let resolved = try #require(
            GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: nil,
                    headURL: "https://github.com/acme/foo.git",
                    stableURL: "https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz",
                    caskDownloadURL: "https://github.com/acme/foo/releases/download/v1.2.0/foo.dmg"
                )
            )
        )

        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "foo"))
        #expect(resolved.source == .headURL)
        #expect(resolved.agreeingSourceCount == 3)
    }

    @Test("The declaration order of the source enumeration is the tie-break order")
    func theDeclarationOrderIsTheTieBreakOrder() {
        #expect(
            RepositorySource.allCases == [.homepage, .headURL, .stableURL, .caskDownloadURL]
        )
    }

    /// The failure this rule exists to prevent, stated as a test: a **refused**
    /// earlier candidate must fall through rather than end resolution.
    ///
    /// Without this, a package whose homepage points at `github.com/settings` or
    /// carries a traversal would report "no repository" while its perfectly good
    /// `urls.stable` sat one field away.
    @Test(
        "A refused earlier candidate falls through to the next source",
        arguments: [
            "https://github.com/settings/billing",
            "https://github.com/../../etc/passwd",
            "https://github.com/acme",
            "https://gitlab.com/acme/foo",
            "not a url at all"
        ]
    )
    func aRefusedEarlierCandidateFallsThrough(homepage: String) throws {
        let resolved = try #require(
            GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: homepage,
                    headURL: nil,
                    stableURL: "https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz",
                    caskDownloadURL: nil
                )
            ),
            "a refused homepage (\(homepage)) blocked a resolvable stableURL"
        )

        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "foo"))
        #expect(resolved.source == .stableURL)
    }

    // MARK: - Hosts and shapes

    @Test(
        "Non-repository and non-GitHub hosts never resolve",
        arguments: [
            "https://gist.github.com/acme/aabbccddeeff00112233445566778899",
            "https://raw.githubusercontent.com/acme/foo/main/README.md",
            "https://acme.github.io/foo",
            "https://gitlab.com/acme/foo",
            "https://codeberg.org/acme/foo",
            "https://bitbucket.org/acme/foo",
            "https://github.example.com/acme/foo",
            "https://notgithub.com/acme/foo",
            "https://github.com.evil.example/acme/foo",
            "https://gnu.org/software/foo",
            "https://python.org",
            "https://videolan.org"
        ]
    )
    func nonRepositoryAndNonGitHubHostsNeverResolve(url: String) {
        let resolved = GitHubRepositoryResolver.resolve(
            RepositoryCandidates(
                homepage: url, headURL: url, stableURL: url, caskDownloadURL: url
            )
        )

        #expect(resolved == nil, "\(url) resolved to \(String(describing: resolved))")
    }

    @Test("Ornamented URLs normalize to one identity")
    func ornamentedUrlsNormalizeToOneIdentity() throws {
        let ornamented = [
            "https://www.github.com/Acme/Foo.git",
            "https://github.com/Acme/Foo/",
            "https://github.com/Acme/Foo/releases/tag/v1.0?utm=x#top",
            "http://GitHub.com/Acme/Foo",
            "https://github.com/Acme/Foo.git/",
            "git://github.com/Acme/Foo.git"
        ]

        var identities: Set<GitHubRepository> = []
        for url in ornamented {
            let resolved = try #require(
                GitHubRepositoryResolver.resolve(
                    RepositoryCandidates(
                        homepage: url, headURL: nil, stableURL: nil, caskDownloadURL: nil
                    )
                ),
                "\(url) did not resolve"
            )
            identities.insert(resolved.repository)
        }

        #expect(identities.count == 1, "the six ornamented URLs produced \(identities)")
        let identity = try #require(identities.first)
        #expect(identity.owner == "Acme")
        #expect(identity.name == "Foo")
        // Stated as characters rather than as equality, because a `.git` that
        // survived would still compare equal to a hand-written expectation
        // somebody wrote after the bug.
        #expect(identity.name.contains(".git") == false)
        #expect(identity.name.contains("/") == false)
        #expect(identity.name.contains("?") == false)
        #expect(identity.name.contains("#") == false)
    }

    /// A repository legitimately *called* something ending in `.git` — the strip
    /// must be a suffix rule on the URL, not a substring rule on the name.
    @Test("Only a trailing .git is stripped, and never from the middle of a name")
    func onlyATrailingGitSuffixIsStripped() throws {
        let resolved = try #require(
            GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: "https://github.com/acme/foo.github.io",
                    headURL: nil, stableURL: nil, caskDownloadURL: nil
                )
            )
        )

        #expect(resolved.repository.name == "foo.github.io")
    }

    // MARK: - Unresolvable is a typed answer

    @Test("A package with four absent fields reports unresolvable, and throws nothing")
    func aPackageWithFourAbsentFieldsReportsUnresolvable() {
        let resolved = GitHubRepositoryResolver.resolve(
            RepositoryCandidates(
                homepage: nil, headURL: nil, stableURL: nil, caskDownloadURL: nil
            )
        )

        #expect(resolved == nil)
    }

    /// Resolution costs nothing, proved by counting.
    ///
    /// **Per-instance, and that is load-bearing.** `RecordingNetwork` owns its own
    /// tagged session and sees only exchanges carrying its own tag, so a
    /// concurrently-running suite cannot add to this count and — the dangerous
    /// direction — cannot reset it either. A process-global counter stood here
    /// first and had to go: `install()` zeroed it, so a sibling suite starting up
    /// could wipe a request this test had already recorded, turning a real egress
    /// into a passing zero.
    ///
    /// The triangulation half is what makes the zero mean something: the same
    /// recorder, in the same test, counts a request when one is actually made.
    @Test("Resolution issues no request at all, and the recorder can count one when it happens")
    func resolutionIssuesNoRequest() async throws {
        let network = RecordingNetwork()

        for _ in 0..<25 {
            _ = GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: "https://gnu.org/software/foo",
                    headURL: nil, stableURL: nil, caskDownloadURL: nil
                )
            )
            _ = GitHubRepositoryResolver.resolve(
                RepositoryCandidates(
                    homepage: "https://github.com/acme/foo",
                    headURL: nil, stableURL: nil, caskDownloadURL: nil
                )
            )
        }

        #expect(network.requestCount == 0, "resolution issued \(network.requestCount) request(s)")

        // The control: the counter is not stuck at zero. Through the recorder's
        // own session, which the recording protocol claims by tag and answers
        // from a stub, so nothing leaves this machine and no other suite's count
        // can be involved either way.
        _ = try? await network.session.data(
            from: URL(string: "https://api.github.com/repos/acme/foo/releases")!
        )
        #expect(network.requestCount == 1, "the recorder did not notice a real request")
    }

    /// The sources actually tried are enumerable, so the unresolvable outcome can
    /// name them rather than shrug. `Phase 5` turns this set into the typed
    /// outcome's payload; here it is asserted where it is produced.
    @Test("The candidate set enumerates every source that was tried")
    func theCandidateSetEnumeratesEverySourceTried() {
        let candidates = RepositoryCandidates(
            homepage: "https://gnu.org/software/foo",
            headURL: nil,
            stableURL: "https://ftp.gnu.org/foo-1.2.0.tar.gz",
            caskDownloadURL: nil
        )

        // Every source is *tried*, including the two that carry nothing: the
        // union rule means absence is a result, not a reason to skip.
        #expect(candidates.triedSources == Set(RepositorySource.allCases))
        #expect(GitHubRepositoryResolver.resolve(candidates) == nil)
    }

    // MARK: - The projection off `CatalogPackage`

    /// The one place this target reads a `Catalog` type, exercised against real
    /// `CatalogPackage` values rather than only against hand-built candidates.
    @Test("Candidates project a formula's homepage and both source URLs")
    func candidatesProjectAFormulasFields() throws {
        let formula = CatalogPackageArrangement.formula(
            homepage: "https://gnu.org/software/foo",
            stableURL: "https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz",
            headURL: "https://github.com/acme/foo.git"
        )

        let candidates = RepositoryCandidates(formula)
        #expect(candidates.homepage == "https://gnu.org/software/foo")
        #expect(candidates.stableURL == "https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz")
        #expect(candidates.headURL == "https://github.com/acme/foo.git")
        #expect(candidates.caskDownloadURL == nil)

        let resolved = try #require(GitHubRepositoryResolver.resolve(candidates))
        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "foo"))
        // Head before stable: the tie-break order, read off a real package.
        #expect(resolved.source == .headURL)
        #expect(resolved.agreeingSourceCount == 2)
    }

    @Test("Candidates project a cask's homepage and download URL")
    func candidatesProjectACasksFields() throws {
        let cask = CatalogPackageArrangement.cask(
            homepage: "https://example.com",
            downloadURL: "https://github.com/acme/tool/releases/download/v3.0/tool.dmg"
        )

        let candidates = RepositoryCandidates(cask)
        #expect(candidates.caskDownloadURL == "https://github.com/acme/tool/releases/download/v3.0/tool.dmg")
        #expect(candidates.stableURL == nil)
        #expect(candidates.headURL == nil)

        let resolved = try #require(GitHubRepositoryResolver.resolve(candidates))
        #expect(resolved.repository == GitHubRepository(owner: "acme", name: "tool"))
        #expect(resolved.source == .caskDownloadURL)
    }

    /// A package carrying neither inspection block projects four absences rather
    /// than crashing on an optional nobody checked.
    @Test("A package with no inspection block projects four absent candidates")
    func aPackageWithNoInspectionBlockProjectsFourAbsences() {
        let bare = CatalogPackageArrangement.formula(homepage: nil)

        let candidates = RepositoryCandidates(bare)
        #expect(candidates.homepage == nil)
        #expect(candidates.headURL == nil)
        #expect(candidates.stableURL == nil)
        #expect(candidates.caskDownloadURL == nil)
        #expect(GitHubRepositoryResolver.resolve(candidates) == nil)
    }
}
