import Foundation
import Testing

@testable import SecurityKit

/// The `InstalledDecoder` rule, restated for a payload nobody in this codebase
/// has decoded before.
///
/// That rule has two halves and they pull in opposite directions. An unreadable
/// **envelope** fails the whole request, because nothing in it is recoverable
/// and a half-read batch would be indistinguishable from a small one. An
/// unreadable **record** costs that record and is *counted*, because one
/// advisory whose shape drifted must not delete every other answer in the batch.
///
/// A third rule exists here that `InstalledDecoder` never needed: OSV's
/// `results` array is **positional**. Entry *i* is the answer to query *i*, and
/// nothing in the entry names the package it belongs to. Skipping a bad entry
/// the way a lossy array skips a bad formula would silently re-attribute every
/// later answer to the wrong package — a whole inventory of confident, wrong
/// findings. So a bad result keeps its slot and reports that it has no answer.
@Suite("OSV wire decode")
struct OSVWireTests {
    // MARK: - The positive anchor

    /// Every absence asserted below is only meaningful if the decoder can read
    /// the real capture at all.
    @Test("The captured querybatch response decodes with every advisory intact")
    func theRealCaptureDecodesCompletely() throws {
        let response = try OSVWire.querybatch(
            from: Fixture.data("OSV/querybatch-affected-response.json")
        )

        #expect(response.results.count == 5)
        #expect(response.skippedRecordCount == 0)

        let identifiers = response.results.flatMap { result -> [String] in
            guard case .answered(let references) = result else { return [] }
            return references.map(\.id)
        }
        #expect(identifiers.count == 19)
        #expect(identifiers.contains("PYSEC-2026-899"))
        #expect(identifiers.contains("GHSA-g4xg-fxmg-vcg5"))
    }

    /// The all-clean capture is a real answer, not a decode failure: seven
    /// queries, seven answered results, zero advisories. This is the shape the
    /// user's real machine produces, so it must decode as `answered([])` — never
    /// as unreadable, and never as an error.
    @Test("An empty result is an answer, not a failure")
    func anEmptyResultDecodesAsAnAnsweredResultWithNoAdvisories() throws {
        let response = try OSVWire.querybatch(
            from: Fixture.data("OSV/querybatch-response.json")
        )

        #expect(response.results.count == 7)
        #expect(response.skippedRecordCount == 0)
        #expect(response.results.allSatisfy { $0 == .answered([]) })
    }

    // MARK: - The envelope

    @Test("A truncated envelope fails the whole request")
    func aMalformedEnvelopeFailsTheRequest() throws {
        let truncated = try Fixture.data("OSV/querybatch-truncated-response.json")

        #expect(throws: AdvisoryError.malformedPayload) {
            try OSVWire.querybatch(from: truncated)
        }
    }

    /// Triangulation with the *other* real way an envelope arrives unreadable:
    /// the captured `429` body is 17 bytes of `text/plain`, not JSON at all.
    /// A decoder that only guarded against truncation would report this as a
    /// successful empty batch.
    @Test("A non-JSON body fails the whole request")
    func aNonJsonBodyFailsTheRequest() throws {
        let rateLimitBody = try Fixture.data("NVD/ratelimited-response.body")

        #expect(rateLimitBody.count == 17, "the captured rate-limit body is not the 17-byte capture")
        #expect(throws: AdvisoryError.malformedPayload) {
            try OSVWire.querybatch(from: rateLimitBody)
        }
    }

    // MARK: - The record

    @Test("A malformed advisory record is skipped and counted, not fatal")
    func aMalformedRecordIsSkippedAndCounted() throws {
        let response = try OSVWire.querybatch(
            from: Fixture.data("OSV/querybatch-badrecord-response.json")
        )

        let result = try #require(response.results.first)
        guard case .answered(let references) = result else {
            Issue.record("the surviving result was not answered")
            return
        }

        // Three records went in; the middle one lost its `id`.
        #expect(references.count == 2)
        #expect(references.map(\.id) == ["GHSA-5689-v88g-g6rv", "GHSA-q5vx-44v4-gch4"])
        #expect(response.skippedRecordCount == 1)
    }

    // MARK: - Position

    /// The hazard this decoder exists to avoid.
    ///
    /// `results[0]` is unreadable. If it were dropped, `results[1]`'s advisories
    /// would be reported against the package that was query 0 — three real CVEs
    /// filed against the wrong formula, with nothing in the payload to catch it.
    /// So the slot survives, holding `.unreadable`, and the later answers stay
    /// where they belong.
    @Test("An unreadable result keeps its slot rather than shifting every later answer")
    func anUnreadableResultDoesNotShiftTheOnesBehindIt() throws {
        let response = try OSVWire.querybatch(
            from: Fixture.data("OSV/querybatch-badresult-response.json")
        )

        #expect(response.results.count == 3)
        #expect(response.results[0] == .unreadable)
        #expect(response.skippedRecordCount == 1)

        guard case .answered(let second) = response.results[1],
              case .answered(let third) = response.results[2]
        else {
            Issue.record("a readable result was reported unreadable")
            return
        }
        #expect(second.map(\.id) == [
            "GHSA-5689-v88g-g6rv", "GHSA-cggh-pq45-6h9x", "GHSA-q5vx-44v4-gch4"
        ])
        #expect(third.map(\.id) == ["GHSA-p24j-h477-76q3", "RUSTSEC-2021-0106"])
    }

    /// `.unreadable` must not be spellable as "clean". The two are different
    /// answers to different questions, and the spec forbids the second from
    /// standing in for the first.
    @Test("An unreadable result is not an empty answer")
    func anUnreadableResultIsNotAnEmptyAnswer() {
        #expect(OSVQueryResult.unreadable != .answered([]))
    }

    // MARK: - Hydration

    @Test("A hydrated advisory carries its identity, aliases, ranges and severity")
    func aHydratedAdvisoryDecodes() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-7gcm-g887-7qv7.json")
        )

        #expect(advisory.id == "GHSA-7gcm-g887-7qv7")
        #expect(advisory.aliases == ["CVE-2026-0994", "PYSEC-2026-1805"])
        #expect(advisory.advertisedSeverity == "HIGH")

        let affected = try #require(advisory.affected.first)
        #expect(affected.ecosystem == "PyPI")
        #expect(affected.packageName == "protobuf")
        #expect(affected.ranges.first?.fixed == ["6.33.5"])
    }

    /// Two real timestamp spellings, both captured. GitHub-sourced records carry
    /// nanosecond fractions; RustSec records carry none at all. A decoder that
    /// handles only one of them silently loses half the corpus.
    @Test(
        "Both captured timestamp spellings parse",
        arguments: [
            ("OSV/vulns-GHSA-p24j-h477-76q3.json", "2023-11-08T04:06:15.992843Z"),
            ("OSV/vulns-RUSTSEC-2020-0163.json", "2022-08-02T14:03:23Z")
        ]
    )
    func bothCapturedTimestampSpellingsParse(path: String, expected: String) throws {
        let advisory = try OSVWire.advisory(from: Fixture.data(path))

        #expect(advisory.modified == OSVWire.timestamp(expected))
        #expect(advisory.modified != Date(timeIntervalSince1970: 0))
    }

    /// The `noFixPublished` / `fixUnknown` distinction the spec requires starts
    /// here, in the payload. RustSec's unmaintained-crate advisories declare an
    /// `introduced` event and no `fixed` event: that is a real "there is no fix",
    /// not a missing field.
    @Test("A range that declares no fixed event is not a missing fix")
    func aRangeWithNoFixedEventIsDistinctFromAnAbsentRange() throws {
        let unmaintained = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-RUSTSEC-2021-0139.json")
        )
        let range = try #require(unmaintained.affected.first?.ranges.first)

        #expect(range.introduced == ["0.0.0-0"])
        #expect(range.fixed.isEmpty)
        #expect(range.lastAffected.isEmpty)

        // Triangulated against a record that does declare a fix, so "empty"
        // above is a fact about the payload and not about the parser.
        let fixed = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )
        #expect(fixed.affected.first?.ranges.first?.fixed == ["0.18.2"])
    }

    @Test("A hydration whose envelope is unreadable fails the request")
    func aMalformedHydrationEnvelopeFails() throws {
        #expect(throws: AdvisoryError.malformedPayload) {
            try OSVWire.advisory(from: Fixture.data("NVD/ratelimited-response.body"))
        }
    }
}
