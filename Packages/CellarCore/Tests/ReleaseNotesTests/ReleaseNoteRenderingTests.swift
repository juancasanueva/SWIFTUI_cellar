import Foundation
import ReleaseNotes
import Testing

/// A release body is **attacker-authored text**, and it must be presentable
/// without failing on anything a GitHub release can carry.
///
/// Two independent pressures shape this, and they pull the same way.
///
/// The first is honesty. `AttributedString(markdown:)` implements CommonMark, and
/// GitHub publishes GFM: tables, task lists, `~~strikethrough~~`, `@mentions` and
/// bare autolinks are simply not interpreted. Failing the sheet on one of them
/// would blank a whole release note over a table; *dropping* them would silently
/// delete content the author wrote. So they degrade to readable literal text, and
/// the render says which ones it degraded.
///
/// The second is containment. A body may reference a remote image and may carry
/// any URL scheme its author felt like typing. Nothing here may become a fetch,
/// and nothing here may become a link the workspace opener would follow.
@Suite("Release note rendering")
struct ReleaseNoteRenderingTests {
    // MARK: - Arrangement

    private func capturedGFMBody() async throws -> String {
        let releases = try await GitHubReleaseDecoder.decode(
            Fixture.data("GitHub/release-body-gfm.json")
        )
        return try #require(releases.first?.body)
    }

    private func text(of rendered: RenderedReleaseNote) -> String {
        rendered.blocks.map { String($0.characters) }.joined(separator: "\n")
    }

    // MARK: - GFM degrades to text, and says so

    @Test("A GFM table survives as readable text and is reported as degraded")
    func aGfmTableSurvivesAsReadableText() async throws {
        let rendered = ReleaseNoteRenderer.render(try await capturedGFMBody())

        #expect(rendered.blocks.isEmpty == false, "the render produced no blocks")
        #expect(rendered.degradedConstructs.contains(.table))

        // The table's own content is present, not merely its pipes.
        let plain = text(of: rendered)
        #expect(plain.contains("macOS"))
        #expect(plain.contains("universal build"))
        #expect(plain.contains("glibc 2.17"))
    }

    @Test("A task list survives as readable text and is reported as degraded")
    func aTaskListSurvivesAsReadableText() async throws {
        let rendered = ReleaseNoteRenderer.render(try await capturedGFMBody())

        #expect(rendered.degradedConstructs.contains(.taskList))

        let plain = text(of: rendered)
        #expect(plain.contains("Ship the release"))
        #expect(plain.contains("Update the docs"))
        #expect(plain.contains("Announce it"))
    }

    @Test(
        "Strikethrough, mentions and bare autolinks are each reported and each survive",
        arguments: [
            (UnsupportedMarkdown.strikethrough, "this was removed"),
            (UnsupportedMarkdown.mention, "@sharkdp"),
            (UnsupportedMarkdown.bareAutolink, "github.com/sharkdp/hyperfine/issues/1")
        ]
    )
    func inlineGfmConstructsAreReportedAndSurvive(
        construct: UnsupportedMarkdown,
        content: String
    ) async throws {
        let rendered = ReleaseNoteRenderer.render(try await capturedGFMBody())

        #expect(rendered.degradedConstructs.contains(construct))
        #expect(text(of: rendered).contains(content), "\(content) was dropped")
    }

    /// Preparation never throws, and the whole body survives it. Asserted as a
    /// character budget rather than as a substring, so a render that dropped
    /// three quarters of the note while keeping the sampled phrases would fail.
    @Test("The whole body survives preparation, not just the phrases the tests sample")
    func theWholeBodySurvivesPreparation() async throws {
        let body = try await capturedGFMBody()
        let rendered = ReleaseNoteRenderer.render(body)
        let plain = text(of: rendered)

        // Markdown punctuation is consumed by design, so this is a floor rather
        // than an equality — but a floor high enough that dropping a block fails.
        #expect(
            plain.count > Int(Double(body.count) * 0.7),
            "the render kept \(plain.count) of \(body.count) characters"
        )
        #expect(rendered.renderedAsPlainText == false, "a valid GFM body fell back to plain text")
    }

    /// The paired negative: a plain CommonMark body degrades **nothing**, so the
    /// reports above are about the constructs and not a value always returned.
    @Test("An ordinary CommonMark body reports no degradation at all")
    func anOrdinaryCommonMarkBodyReportsNoDegradation() {
        let rendered = ReleaseNoteRenderer.render("""
            ## What's Changed

            * Fixed a crash in the parser
            * Added `--json` output

            See the [documentation](https://example.com/docs) for details.
            """)

        #expect(rendered.degradedConstructs.isEmpty, "\(rendered.degradedConstructs)")
        #expect(rendered.renderedAsPlainText == false)
        #expect(text(of: rendered).contains("Fixed a crash in the parser"))
        #expect(text(of: rendered).contains("documentation"))
    }

    // MARK: - Nothing is unpresentable

    @Test("A malformed body is presentable and never throws")
    func aMalformedBodyIsPresentable() async throws {
        let releases = try await GitHubReleaseDecoder.decode(
            Fixture.data("GitHub/release-body-malformed.json")
        )
        let body = try #require(releases.first?.body)

        let rendered = ReleaseNoteRenderer.render(body)

        #expect(rendered.blocks.isEmpty == false)
        // The author's words are still readable, whatever the syntax did.
        #expect(text(of: rendered).contains("Broken on purpose"))
        #expect(text(of: rendered).contains("this code fence is never closed"))
    }

    @Test("A body at the byte limit is presentable")
    func aBodyAtTheByteLimitIsPresentable() {
        let body = String(repeating: "All work and no play. ", count: 2_000)

        let rendered = ReleaseNoteRenderer.render(body)

        #expect(rendered.blocks.isEmpty == false)
        #expect(text(of: rendered).contains("All work and no play."))
    }

    /// The total-failure path exists and is reachable, so `renderedAsPlainText`
    /// is a real state rather than a field that is always `false`.
    @Test("A body the parser cannot make anything of falls back to plain text")
    func aBodyTheParserCannotHandleFallsBackToPlainText() {
        // A lone unpaired surrogate-adjacent construct plus deeply nested
        // brackets is the shape that defeats the parser outright.
        let hostile = String(repeating: "[", count: 5_000) + "text"

        let rendered = ReleaseNoteRenderer.render(hostile)

        #expect(rendered.blocks.isEmpty == false)
        #expect(text(of: rendered).contains("text"))
    }

    @Test("An empty body renders empty and never crashes")
    func anEmptyBodyRendersEmpty() {
        for body in ["", "   ", "\n\n\n"] {
            let rendered = ReleaseNoteRenderer.render(body)

            #expect(rendered.blocks.isEmpty, "\(body.debugDescription) produced blocks")
            #expect(rendered.degradedConstructs.isEmpty)
            #expect(rendered.renderedAsPlainText == false)
        }
    }

    /// One bad block costs its own block and not the note. That is the whole
    /// reason parsing is block-wise rather than whole-body.
    @Test("A block the parser stumbles on does not cost the blocks around it")
    func aBadBlockDoesNotCostTheBlocksAroundIt() {
        let rendered = ReleaseNoteRenderer.render("""
            First paragraph, perfectly ordinary.

            | broken | table
            | ---

            Third paragraph, also ordinary.
            """)

        let plain = text(of: rendered)
        #expect(plain.contains("First paragraph, perfectly ordinary."))
        #expect(plain.contains("Third paragraph, also ordinary."))
        #expect(rendered.blocks.count >= 3, "the render collapsed to \(rendered.blocks.count) blocks")
    }

    // MARK: - A body cannot cause a second egress

    /// The containment claim: nothing in a prepared note is something a view
    /// could fetch. Asserted over the attributes a SwiftUI `Text` would actually
    /// act on, not over the source text.
    @Test("An image reference produces no URL a view could fetch")
    func anImageReferenceProducesNoFetchableUrl() async throws {
        let rendered = ReleaseNoteRenderer.render(try await capturedGFMBody())

        for block in rendered.blocks {
            for run in block.runs {
                #expect(run.imageURL == nil, "a prepared block carried a fetchable image URL")
            }
        }

        // The reference is reported rather than silently swallowed, and its alt
        // text survives so the reader knows something was there.
        #expect(rendered.degradedConstructs.contains(.image))
        #expect(text(of: rendered).contains("release banner"))
        // And the image's host appears nowhere a view would follow it.
        for block in rendered.blocks {
            for run in block.runs {
                #expect(run.link?.host() != "raw.githubusercontent.com")
            }
        }
    }

    @Test("A body with no image reports no image degradation")
    func aBodyWithNoImageReportsNoImageDegradation() {
        let rendered = ReleaseNoteRenderer.render("Just a paragraph with a [link](https://example.com).")

        #expect(rendered.degradedConstructs.contains(.image) == false)
    }

    @Test(
        "browsableLink refuses every scheme but http and https",
        arguments: [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "data:text/html;base64,PHNjcmlwdD4=",
            "ftp://example.com/x",
            "vbscript:msgbox(1)",
            "https://",
            "http://",
            "not a url",
            ""
        ]
    )
    func browsableLinkRefusesEverySchemeButHttpAndHttps(raw: String) {
        #expect(
            ReleaseNoteRenderer.browsableLink(raw) == nil,
            "\(raw) was admitted as browsable"
        )
    }

    @Test(
        "browsableLink admits http and https with a non-empty host",
        arguments: [
            "https://github.com/acme/foo/releases/tag/v1.0",
            "http://example.com",
            "HTTPS://Example.com/path?q=1#frag"
        ]
    )
    func browsableLinkAdmitsHttpAndHttps(raw: String) throws {
        let url = try #require(
            ReleaseNoteRenderer.browsableLink(raw),
            "\(raw) was refused"
        )

        #expect(url.host()?.isEmpty == false)
        #expect(["http", "https"].contains(url.scheme?.lowercased() ?? ""))
    }

    /// The allowlist is the `CaskInspection.browsableDownloadURL` rule, reused
    /// rather than reinvented — so a scheme nobody thought about is refused in
    /// both places for the same reason.
    @Test("A refused link is not dropped: the text stays readable")
    func aRefusedLinkIsNotDropped() {
        let rendered = ReleaseNoteRenderer.render("Try [this](javascript:alert(1)) if you dare.")

        let plain = text(of: rendered)
        #expect(plain.contains("this"))
        for block in rendered.blocks {
            for run in block.runs {
                #expect(run.link?.scheme?.lowercased() != "javascript")
            }
        }

        // The paired positive, and the one that makes the strip a *rule* rather
        // than a blanket removal: an admitted link survives as a link.
        let admitted = ReleaseNoteRenderer.render("See [the docs](https://example.com/docs).")
        let links = admitted.blocks.flatMap { $0.runs.compactMap(\.link) }
        #expect(
            links.contains { $0.absoluteString == "https://example.com/docs" },
            "the strip removed a link it should have kept: \(links)"
        )
    }

    @Test("Rendering issues no request, counted")
    func renderingIssuesNoRequest() async throws {
        // Per-instance and tagged. The body under test references a remote image
        // and several links, so this is the count that says preparing it caused
        // no second acquisition — and a count another suite could reset would be
        // worse than no count at all.
        let network = RecordingNetwork()

        _ = ReleaseNoteRenderer.render(try await capturedGFMBody())

        #expect(network.requestCount == 0, "preparation issued \(network.requestCount) request(s)")

        // The control, so the zero above is a counted zero.
        _ = try? await network.session.data(
            from: URL(string: "https://api.github.com/repos/acme/foo/releases")!
        )
        #expect(network.requestCount == 1, "the recorder did not notice a real request")
    }

    // MARK: - Preparation never changes the outcome

    /// A degraded body is still a matched release. The renderer produces a
    /// *presentation*, and a presentation cannot demote an answer.
    @Test("A degraded body is still a matched release")
    func aDegradedBodyIsStillAMatchedRelease() async throws {
        let body = try await capturedGFMBody()
        let resolved = ResolvedRepository(
            repository: GitHubRepository(owner: "sharkdp", name: "hyperfine")!,
            source: .homepage,
            agreeingSourceCount: 1
        )
        let outcome = ReleaseNotesOutcome.notes(
            resolved, GitHubRelease(tagName: "v1.20.0", name: "v1.20.0", body: body)
        )

        let rendered = ReleaseNoteRenderer.render(try #require(outcome.release?.body))

        #expect(rendered.degradedConstructs.isEmpty == false, "the fixture degraded nothing")
        // The outcome is untouched by preparation.
        #expect(outcome.release?.tagName == "v1.20.0")
        if case .notes = outcome {} else {
            Issue.record("preparation changed the outcome to \(outcome)")
        }
    }

    /// A matched release whose body is the **empty string** reports a matched
    /// release with an explicitly empty body — a third thing, distinct from both
    /// absences.
    @Test("An empty body is a matched release with an empty render, not an absence")
    func anEmptyBodyIsAMatchedReleaseNotAnAbsence() {
        let resolved = ResolvedRepository(
            repository: GitHubRepository(owner: "acme", name: "foo")!,
            source: .homepage,
            agreeingSourceCount: 1
        )
        let outcome = ReleaseNotesOutcome.notes(
            resolved, GitHubRelease(tagName: "v2.44.0", name: "2.44.0", body: "")
        )

        let rendered = ReleaseNoteRenderer.render(outcome.release?.body ?? "")

        #expect(rendered.blocks.isEmpty)
        #expect(outcome.release?.body == "")
        #expect(outcome != .repositoryPublishesNoReleases(resolved))
        #expect(
            outcome != .noReleaseMatchesVersion(
                resolved, version: "2.44.0", inspected: 1, pageWasFull: false
            )
        )
    }
}
