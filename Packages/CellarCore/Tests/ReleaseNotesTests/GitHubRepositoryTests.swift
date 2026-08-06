import Foundation
import ReleaseNotes
import Testing

/// A repository identity is the one place attacker-influenceable catalog text
/// becomes a **URL path**, so a malformed one must be unrepresentable.
///
/// This is the `FormulaID` / `CaskID` / `MutationName.isSafe` discipline applied
/// one boundary over. Homebrew's published `homepage` and `url` fields are
/// third-party text: a tap can publish anything, and this capability turns two
/// segments of it into `/repos/{owner}/{repo}/releases`. A value carrying `..`,
/// a slash, a percent-escape or whitespace does not get sanitised on the way
/// out — it never becomes a `GitHubRepository` at all.
@Suite("GitHub repository identity")
struct GitHubRepositoryTests {
    // MARK: - What is accepted

    @Test("A legal owner and name produce a repository carrying both verbatim")
    func aLegalOwnerAndNameProduceARepository() throws {
        let repository = try #require(GitHubRepository(owner: "acme", name: "foo"))

        #expect(repository.owner == "acme")
        #expect(repository.name == "foo")
    }

    /// The three punctuation characters GitHub really does allow, asserted
    /// positively so the refusals below are a rule and not a blanket ban.
    @Test(
        "Dots, dashes and underscores are legal in both segments",
        arguments: [
            ("sharkdp", "hyperfine"),
            ("BurntSushi", "ripgrep"),
            ("cellar-app", "cellar.core"),
            ("some_owner", "some_name-2.0"),
            ("a", "b")
        ]
    )
    func dotsDashesAndUnderscoresAreLegal(owner: String, name: String) throws {
        let repository = try #require(
            GitHubRepository(owner: owner, name: name),
            "\(owner)/\(name) was refused"
        )

        #expect(repository.owner == owner)
        #expect(repository.name == name)
    }

    // MARK: - What is refused

    @Test(
        "A traversal, an escape, whitespace or an illegal character is unrepresentable",
        arguments: [
            ("..", "foo"), ("acme", ".."),
            (".", "foo"), ("acme", "."),
            ("", "foo"), ("acme", ""),
            ("../etc", "foo"), ("acme", "../../etc/passwd"),
            ("acme/evil", "foo"), ("acme", "foo/bar"),
            ("%2e%2e", "foo"), ("acme", "fo%2fo"),
            ("ac me", "foo"), ("acme", "fo o"),
            ("acme\n", "foo"), ("acme", "foo\t"),
            ("acme?x=1", "foo"), ("acme", "foo#top"),
            ("acme:8080", "foo"), ("acme", "foo@bar"),
            ("acmé", "foo"), ("acme", "föo"),
            ("acme\\evil", "foo"), ("acme", "foo&bar")
        ]
    )
    func anIllegalSegmentIsUnrepresentable(owner: String, name: String) {
        #expect(
            GitHubRepository(owner: owner, name: name) == nil,
            "\(owner)/\(name) produced a repository"
        )
    }

    /// GitHub's own non-repository paths sit at the same depth as an owner, so
    /// `github.com/settings/billing` looks exactly like `github.com/acme/foo` to
    /// a two-segment reader. A denylist here is what stops that shape from
    /// becoming a request for somebody's settings page.
    @Test(
        "GitHub's reserved first segments never name an owner",
        arguments: [
            "settings", "login", "logout", "join", "explore", "marketplace",
            "sponsors", "notifications", "new", "orgs", "organizations", "account",
            "apps", "topics", "collections", "trending", "events", "codespaces",
            "pulls", "issues", "search", "sessions", "users", "dashboard", "stars",
            "watching", "gist", "about", "pricing", "features", "security", "site",
            "blog", "contact", "enterprise", "nonprofit", "customer-stories"
        ]
    )
    func gitHubsReservedFirstSegmentsNeverNameAnOwner(reserved: String) {
        #expect(
            GitHubRepository(owner: reserved, name: "foo") == nil,
            "the reserved segment \(reserved) was accepted as an owner"
        )
    }

    /// Case-insensitively, because `github.com/Settings` is the same page.
    @Test("A reserved segment is refused whatever its case")
    func aReservedSegmentIsRefusedWhateverItsCase() {
        #expect(GitHubRepository(owner: "Settings", name: "foo") == nil)
        #expect(GitHubRepository(owner: "SETTINGS", name: "foo") == nil)
        // The other direction: the reservation is on the *owner* slot only, so a
        // repository legitimately called `settings` is still representable.
        #expect(GitHubRepository(owner: "acme", name: "settings") != nil)
    }

    // MARK: - Value semantics

    @Test("Two repositories with the same segments are the same value, and it round-trips")
    func theIdentityIsAValueThatRoundTrips() throws {
        let first = try #require(GitHubRepository(owner: "acme", name: "foo"))
        let second = try #require(GitHubRepository(owner: "acme", name: "foo"))
        let other = try #require(GitHubRepository(owner: "acme", name: "bar"))

        #expect(first == second)
        #expect(first != other)
        #expect(Set([first, second, other]).count == 2)

        let encoded = try JSONEncoder().encode(first)
        #expect(try JSONDecoder().decode(GitHubRepository.self, from: encoded) == first)
    }

    /// Comparison is **case-sensitive** on purpose: `Acme/Foo` and `acme/foo` are
    /// the same repository to GitHub, but normalising case here would mean a
    /// resolved repository no longer carries the text the catalog published, and
    /// the provenance claim would stop being checkable against the source URL.
    /// Normalisation is the resolver's job, and only for the *host*.
    @Test("Segment comparison preserves the published case")
    func segmentComparisonPreservesThePublishedCase() throws {
        let published = try #require(GitHubRepository(owner: "Acme", name: "Foo"))

        #expect(published.owner == "Acme")
        #expect(published.name == "Foo")
    }
}
