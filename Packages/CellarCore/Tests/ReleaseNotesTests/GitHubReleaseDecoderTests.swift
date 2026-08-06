import Foundation
import ReleaseNotes
import Testing

/// The wire, decoded from captured bodies rather than from strings written here.
///
/// Every fixture below is a real `api.github.com` response (see
/// `Fixtures/GitHub/README.md` for the two authored exceptions and why they are
/// authored), so a field GitHub renames breaks this suite rather than silently
/// producing empty release notes in the sheet.
@Suite("GitHub release decoding")
struct GitHubReleaseDecoderTests {
    // MARK: - A populated page

    @Test("A populated page decodes to every release it carried, with all seven fields")
    func aPopulatedPageDecodesToEveryRelease() async throws {
        let releases = try await GitHubReleaseDecoder.decode(
            Fixture.data("GitHub/releases-git-populated.json")
        )

        // The capture is `sharkdp/hyperfine` at `per_page=30`, which answered 26.
        #expect(releases.count == 26, "the capture decoded to \(releases.count) releases")

        let newest = try #require(releases.first)
        #expect(newest.tagName == "v1.20.0")
        #expect(newest.name?.isEmpty == false)
        #expect(newest.body?.isEmpty == false)
        #expect(newest.isDraft == false)
        #expect(newest.isPrerelease == false)
        #expect(newest.htmlURL?.absoluteString.contains("sharkdp/hyperfine") == true)

        let published = try #require(newest.publishedAt)
        // A real instant, not `Date()` and not the epoch: the strategy actually
        // parsed the published ISO-8601 string.
        #expect(published > Date(timeIntervalSince1970: 1_600_000_000))
        #expect(published < Date(timeIntervalSince1970: 1_800_000_000))

        // Every element carries a tag; a release without one is not a release.
        #expect(releases.allSatisfy { $0.tagName.isEmpty == false })
        #expect(Set(releases.map(\.tagName)).count == releases.count, "tags were not unique")
    }

    /// The prerelease flag decoded off a **published** prerelease rather than an
    /// invented one — `sharkdp/vivid` really did ship `v0.11.1-pre`.
    @Test("A published prerelease decodes with its flag set, and its siblings do not")
    func aPublishedPrereleaseDecodesWithItsFlagSet() async throws {
        let releases = try await GitHubReleaseDecoder.decode(
            Fixture.data("GitHub/releases-no-matching-tag.json")
        )

        let prerelease = try #require(releases.first { $0.tagName == "v0.11.1-pre" })
        #expect(prerelease.isPrerelease)

        let stable = try #require(releases.first { $0.tagName == "v0.11.1" })
        #expect(stable.isPrerelease == false)
    }

    // MARK: - An empty page

    /// `[]` is a value, not a failure and not a `nil`. It is what makes "the
    /// repository publishes no releases" answerable from one request.
    @Test("An empty page decodes to an empty array, not to nil and not to a throw")
    func anEmptyPageDecodesToAnEmptyArray() async throws {
        let releases = try await GitHubReleaseDecoder.decode(
            Fixture.data("GitHub/releases-empty.json")
        )

        // The setup is what makes this emptiness meaningful: `git/git` genuinely
        // publishes no GitHub releases, and the capture is five bytes long.
        #expect(releases.isEmpty)
    }

    // MARK: - Tolerance

    /// One bad element costs that element and nothing else.
    ///
    /// The `LossyArray` discipline the catalog already uses on ~16,000 published
    /// records, applied here for the same reason: a release whose shape drifted
    /// must not blank a page of twenty-nine good ones.
    @Test("A malformed element is skipped without costing the rest of the page")
    func aMalformedElementIsSkippedWithoutCostingThePage() async throws {
        let payload = Data("""
            [
              {"tag_name": "v1.0.0", "name": "First", "body": "one",
               "draft": false, "prerelease": false,
               "published_at": "2024-01-01T00:00:00Z",
               "html_url": "https://github.com/acme/foo/releases/tag/v1.0.0"},
              {"name": "no tag at all", "draft": false, "prerelease": false},
              "a bare string where an object belongs",
              {"tag_name": "v0.9.0", "name": "Older", "body": "two",
               "draft": false, "prerelease": false,
               "published_at": "2023-01-01T00:00:00Z",
               "html_url": "https://github.com/acme/foo/releases/tag/v0.9.0"}
            ]
            """.utf8)

        let releases = try await GitHubReleaseDecoder.decode(payload)

        #expect(releases.count == 2, "the tolerant decode produced \(releases.map(\.tagName))")
        #expect(releases.map(\.tagName) == ["v1.0.0", "v0.9.0"])
        #expect(releases[0].body == "one")
    }

    /// Optional fields really are optional: GitHub publishes `null` for the name
    /// and body of a release created from a bare tag.
    @Test("A release with a null name and body decodes rather than being skipped")
    func aReleaseWithNullNameAndBodyDecodes() async throws {
        let payload = Data("""
            [{"tag_name": "v2.0.0", "name": null, "body": null,
              "draft": false, "prerelease": false,
              "published_at": null, "html_url": null}]
            """.utf8)

        let releases = try await GitHubReleaseDecoder.decode(payload)

        #expect(releases.count == 1)
        #expect(releases[0].tagName == "v2.0.0")
        #expect(releases[0].name == nil)
        #expect(releases[0].body == nil)
        #expect(releases[0].publishedAt == nil)
        #expect(releases[0].htmlURL == nil)
    }

    /// A payload that is not an array at all is a **failure**, not an empty page.
    ///
    /// This is the distinction the whole outcome set turns on: GitHub answers an
    /// error with a JSON *object*, and decoding that leniently to `[]` would
    /// report a 403 as "this repository publishes no releases".
    @Test(
        "A payload that is not a release array throws rather than decoding to empty",
        arguments: [
            "GitHub/error-403-ratelimit.json",
            "GitHub/error-401-unauthorized.json",
            "GitHub/error-404-repo.json"
        ]
    )
    func anErrorPayloadThrowsRatherThanDecodingToEmpty(path: String) async throws {
        let payload = try Fixture.data(path)

        await #expect(throws: (any Error).self) {
            try await GitHubReleaseDecoder.decode(payload)
        }
    }

    @Test("Bytes that are not JSON at all throw")
    func bytesThatAreNotJsonThrow() async {
        await #expect(throws: (any Error).self) {
            try await GitHubReleaseDecoder.decode(Data("not json".utf8))
        }
    }
}
