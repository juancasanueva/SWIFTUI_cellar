import Foundation

/// One GitHub repository, by owner and name, validated at construction.
///
/// ## Why this is failable rather than two strings
///
/// This value is the only place attacker-influenceable catalog text becomes a
/// **URL path**. Homebrew's `homepage`, `urls.stable`, `urls.head` and a cask's
/// `url` are third-party text — a tap can publish anything — and this capability
/// splices two segments of it into `/repos/{owner}/{repo}/releases`. A segment
/// carrying `..`, a slash, a percent-escape, a query character or whitespace
/// could change the path, add a parameter, or leave the resource entirely.
///
/// So there is no sanitising step on the way out. A malformed repository is
/// *unrepresentable*: the `init?` refuses it, and every layer downstream can
/// treat an existing `GitHubRepository` as already safe. That is the same
/// discipline `FormulaID`, `CaskID` and `MutationName.isSafe` apply to argv, one
/// boundary over.
///
/// ## Why the case is preserved
///
/// GitHub treats `Acme/Foo` and `acme/foo` as the same repository, so lowercasing
/// here would be harmless for requests — and would quietly break the *provenance*
/// claim, because a resolved repository could no longer be checked against the
/// URL that produced it. Normalisation belongs to the resolver, and only for the
/// host.
public struct GitHubRepository: Sendable, Hashable, Codable {
    public let owner: String
    public let name: String

    /// Fails on anything outside `[A-Za-z0-9._-]`, on `.` and `..`, on an empty
    /// segment, and on GitHub's own reserved first segments.
    public init?(owner: String, name: String) {
        guard Self.isLegalSegment(owner),
              Self.isLegalSegment(name),
              Self.reservedOwners.contains(owner.lowercased()) == false
        else { return nil }

        self.owner = owner
        self.name = name
    }

    /// `owner/name`, for a message a human reads. Never used to build a request:
    /// the two segments are interpolated separately so a joined string can never
    /// be split back apart wrongly.
    public var slug: String { "\(owner)/\(name)" }

    // MARK: - The alphabet

    /// Exhaustive and positive. A character is legal by being on this list, so
    /// one nobody thought about is refused rather than allowed — which is the
    /// only direction a boundary like this may fail in.
    ///
    /// ASCII by construction: `isLetter` on a `Character` would admit `é` and
    /// every other Unicode letter, and a non-ASCII owner is not a GitHub owner.
    private static func isLegalSegment(_ segment: String) -> Bool {
        guard segment.isEmpty == false, segment != ".", segment != ".." else { return false }
        return segment.utf8.allSatisfy { byte in
            (byte >= 0x41 && byte <= 0x5A)       // A-Z
                || (byte >= 0x61 && byte <= 0x7A) // a-z
                || (byte >= 0x30 && byte <= 0x39) // 0-9
                || byte == 0x2E                   // .
                || byte == 0x5F                   // _
                || byte == 0x2D                   // -
        }
    }

    /// GitHub's own non-repository paths sit at the **same depth** as an owner:
    /// `github.com/settings/billing` is shaped exactly like `github.com/acme/foo`
    /// to a reader that takes the first two segments. Without this list a
    /// published link to a settings, sponsors or marketplace page would resolve
    /// to a "repository" and become a request.
    ///
    /// The reservation applies to the **owner slot only**. A repository genuinely
    /// named `settings` is legitimate and stays representable.
    private static let reservedOwners: Set<String> = [
        "about", "account", "apps", "blog", "collections", "contact", "codespaces",
        "customer-stories", "dashboard", "enterprise", "events", "explore",
        "features", "gist", "issues", "join", "login", "logout", "marketplace",
        "new", "nonprofit", "notifications", "organizations", "orgs", "pricing",
        "pulls", "search", "security", "sessions", "settings", "site", "sponsors",
        "stars", "topics", "trending", "users", "watching"
    ]
}
