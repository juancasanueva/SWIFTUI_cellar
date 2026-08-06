import Catalog
import Foundation

// MARK: - Provenance

/// Which published field produced a repository.
///
/// **Declaration order is the tie-break order.** `CaseIterable` is derived from
/// it, and the resolver iterates `allCases`, so the two can never drift apart
/// into a documented order and an executed one.
public enum RepositorySource: String, Sendable, Hashable, Codable, CaseIterable {
    case homepage
    case headURL
    case stableURL
    case caskDownloadURL
}

// MARK: - Candidates

/// The four published values a repository may be derived from.
///
/// **This is the only place in the target that reads a `Catalog` type**, and it
/// reads four *URL* fields and no digest field of either kind. See
/// `Fixtures/GitHub/README.md` for why that is a decision rather than an
/// oversight: a formula's digest is `urls.stable.checksum`, deliberately out of
/// scope since slice 1, and a cask's is `CaskInspection.declaredChecksum`.
/// Nothing in release notes has any use for either.
public struct RepositoryCandidates: Sendable, Hashable {
    public let homepage: String?
    public let headURL: String?
    public let stableURL: String?
    public let caskDownloadURL: String?

    public init(homepage: String?, headURL: String?, stableURL: String?, caskDownloadURL: String?) {
        self.homepage = homepage
        self.headURL = headURL
        self.stableURL = stableURL
        self.caskDownloadURL = caskDownloadURL
    }

    public init(_ package: CatalogPackage) {
        self.init(
            homepage: package.homepage?.absoluteString,
            headURL: package.formulaSources?.headURL,
            stableURL: package.formulaSources?.stableURL,
            caskDownloadURL: package.caskInspection?.downloadURL
        )
    }

    public func value(for source: RepositorySource) -> String? {
        switch source {
        case .homepage: homepage
        case .headURL: headURL
        case .stableURL: stableURL
        case .caskDownloadURL: caskDownloadURL
        }
    }

    /// Every source, always — including the ones carrying nothing.
    ///
    /// Under a union rule an absent field is a field that was *tried and gave no
    /// answer*, not a field that was skipped, and the unresolvable outcome says
    /// so. Reporting only the populated ones would let "we looked everywhere and
    /// found nothing" and "there was nothing to look at" read identically.
    public var triedSources: Set<RepositorySource> { Set(RepositorySource.allCases) }
}

// MARK: - The answer

/// A repository, and the evidence for the claim.
///
/// `source` is what makes the claim inspectable: every resolved repository names
/// the URL that produced it, so a wrong answer can be traced to a wrong field
/// instead of to "the resolver". `agreeingSourceCount` makes U5's measured
/// property — the fields disagreed **zero** times — observable at runtime rather
/// than only in a probe report.
public struct ResolvedRepository: Sendable, Hashable, Codable {
    public let repository: GitHubRepository
    public let source: RepositorySource
    public let agreeingSourceCount: Int

    public init(repository: GitHubRepository, source: RepositorySource, agreeingSourceCount: Int) {
        self.repository = repository
        self.source = source
        self.agreeingSourceCount = agreeingSourceCount
    }
}

// MARK: - The resolver

/// Derives a GitHub repository from a package's published URLs.
///
/// ## Union, not precedence
///
/// Every one of the four fields is evaluated, every time. The first field that
/// yields a repository, in `RepositorySource` declaration order, is *credited* —
/// but the evaluation never stops early, because a field that yields nothing must
/// not prevent a later one from answering, and a field that yields something
/// *refused* (a traversal, a reserved owner, a non-GitHub host) must fall through
/// rather than end resolution.
///
/// U5 measured why this ordering is only a tie-break: `homepage` resolves 24.5%
/// of installed formulae and `urls.stable` 54.7%, and where more than one yielded
/// a repository they **never disagreed**. Precedence therefore buys which field
/// gets the credit and nothing else.
///
/// ## What this never does
///
/// No request, no `brew` process, no cache read, and no search, name-similarity
/// or vendor-guessing step. It is a `nonisolated static` pure function of the
/// values it is handed, which is what lets an app decide whether to *offer* the
/// action at all without paying anything for the question.
public enum GitHubRepositoryResolver {
    public nonisolated static func resolve(_ candidates: RepositoryCandidates) -> ResolvedRepository? {
        // Every source, in declaration order, with no early exit.
        let yielded: [(source: RepositorySource, repository: GitHubRepository)] =
            RepositorySource.allCases.compactMap { source in
                guard let raw = candidates.value(for: source),
                      let repository = repository(from: raw)
                else { return nil }
                return (source, repository)
            }

        guard let winner = yielded.first else { return nil }

        return ResolvedRepository(
            repository: winner.repository,
            source: winner.source,
            agreeingSourceCount: yielded.count { $0.repository == winner.repository }
        )
    }

    // MARK: - One URL

    /// The published text read as a repository, or nothing.
    ///
    /// Deliberately not `public`: the only supported entry point is `resolve`,
    /// which applies the union rule. A public single-URL reader would be an
    /// invitation to re-implement precedence at a call site.
    nonisolated static func repository(from raw: String) -> GitHubRepository? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              Self.acceptedSchemes.contains(scheme),
              let host = components.host?.lowercased(),
              Self.isGitHubHost(host)
        else { return nil }

        // Query and fragment are already separated by `URLComponents`; any path
        // segment past the second is dropped rather than made part of the
        // identity, which is what collapses `/releases/tag/v1.0` and
        // `/archive/refs/tags/v1.tar.gz` onto the same repository.
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count >= 2 else { return nil }

        let owner = String(segments[0])
        var name = String(segments[1])
        // A **suffix** rule, not a substring one: `foo.github.io` keeps its name,
        // and only a repository URL written `…/foo.git` loses four characters.
        if name.hasSuffix(".git") { name.removeLast(4) }

        return GitHubRepository(owner: owner, name: name)
    }

    /// `github.com`, and `www.github.com` because Homebrew records both.
    ///
    /// An exact comparison after stripping exactly one `www.` prefix, never a
    /// `hasSuffix("github.com")`: that would admit `github.com.evil.example`,
    /// which is a different host entirely and is the classic way this check is
    /// got wrong. `gist.github.com`, `raw.githubusercontent.com` and every
    /// `*.github.io` page fail the same comparison and never resolve.
    private nonisolated static func isGitHubHost(_ host: String) -> Bool {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare == "github.com"
    }

    /// Homebrew publishes `head` URLs as `git://` as well as `https://`, so the
    /// list is three long. Exhaustive and positive: the input scheme is only ever
    /// used to decide whether the text is a repository URL — every request this
    /// capability issues is built from a compiled-in `https` base — but admitting
    /// `file:` or `javascript:` here would still be admitting a value nobody
    /// examined.
    private static let acceptedSchemes: Set<String> = ["https", "http", "git"]
}
