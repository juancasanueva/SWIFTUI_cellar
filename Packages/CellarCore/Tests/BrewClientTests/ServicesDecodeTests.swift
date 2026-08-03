import Foundation
import Testing

@testable import BrewClient

/// The services decoders, over fixtures rather than over a live probe.
///
/// The reason is stated once, in `ServicesFixture`, and it governs this whole
/// suite: six of the seven statuses cannot be produced on the development
/// machine, so a decoder proven only against what `atuin` happens to report
/// would be proven against one value.
@Suite("Services decoding")
struct ServicesDecodeTests {
    private func services(_ payload: String) throws -> [ServiceRecord] {
        try ServicesDecoder.services(from: Data(payload.utf8))
    }

    private func detail(_ payload: String) throws -> ServiceDetail {
        let details = try ServicesDecoder.details(from: Data(payload.utf8))
        return try #require(details.first)
    }

    // MARK: - SM1 — the seven statuses

    @Test("All seven statuses decode to their own case")
    func allSevenStatusesDecodeToTheirOwnCase() throws {
        let decoded = try services(ServicesFixture.allStatuses)

        #expect(decoded.count == 7)
        #expect(
            decoded.map(\.status) == [
                .started, .none, .scheduled, .stopped, .error, .unknown, .other
            ]
        )
        // Distinct cases, not seven spellings of one: a decoder folding the six
        // it cannot observe into a catch-all would still satisfy a count.
        #expect(Set(decoded.map(\.status)).count == 7)
        #expect(decoded.map(\.name) == [
            "started-one", "none-one", "scheduled-one", "stopped-one",
            "error-one", "unknown-one", "other-one"
        ])
    }

    @Test("An unrecognised status preserves the raw string and never fails the payload")
    func anUnrecognisedStatusPreservesTheRawStringAndNeverFailsThePayload() throws {
        let decoded = try services(ServicesFixture.withUnrecognisedStatus)

        #expect(decoded.count == 3, "one unreadable status cost the whole payload")
        #expect(decoded.map(\.name) == ["atuin", "postgresql", "enigma"])
        #expect(decoded[0].status == .started)
        #expect(decoded[1].status == .none)
        #expect(decoded[2].status == .unrecognised("mystery"))
        // The raw string survives, so the row can show what brew actually said
        // rather than hiding the service or inventing a status for it.
        #expect(decoded[2].status.raw == "mystery")
    }

    /// brew's own vocabulary contains a value literally called `other`, so the
    /// catch-all cannot be named after it. This is the assertion that keeps the
    /// two apart.
    @Test("brew's own other status is not the catch-all")
    func brewsOwnOtherStatusIsNotTheCatchAll() throws {
        let decoded = try services(ServicesFixture.list([
            ServicesFixture.record(name: "real-other", status: "other"),
            ServicesFixture.record(name: "made-up", status: "otherish")
        ]))

        #expect(decoded[0].status == .other)
        #expect(decoded[1].status == .unrecognised("otherish"))
        #expect(decoded[0].status != decoded[1].status)
    }

    @Test("An undecodable record is skipped rather than failing the payload")
    func anUndecodableRecordIsSkippedRatherThanFailingThePayload() throws {
        let decoded = try services(ServicesFixture.withUndecodableRecord)

        #expect(decoded.count == 1, "a nameless record took a healthy one with it")
        #expect(decoded[0].name == "atuin")
        #expect(decoded[0].status == .started)
    }

    @Test("A payload that is not a list at all is malformed")
    func aPayloadThatIsNotAListIsMalformed() {
        #expect(throws: ServicesError.malformedPayload) {
            _ = try services(ServicesFixture.notAList)
        }
    }

    // MARK: - SM1 — nullable keys

    @Test("A null user and null exit code decode as absent")
    func aNullUserAndNullExitCodeDecodeAsAbsent() throws {
        let decoded = try services(ServicesFixture.withNullUserAndExitCode)
        let service = try #require(decoded.first)

        #expect(service.user == nil, "a null user was replaced by a default")
        #expect(service.exitCode == nil, "a null exit code was replaced by a default")
        // And the record around them arrived intact, so "absent" is not a
        // synonym for "the record was dropped".
        #expect(service.name == "atuin")
        #expect(service.status == .none)
        #expect(service.plistPath?.lastPathComponent == "homebrew.mxcl.atuin.plist")
    }

    @Test("A present user and exit code are carried through")
    func aPresentUserAndExitCodeAreCarriedThrough() throws {
        let decoded = try services(ServicesFixture.allStatuses)
        let failed = try #require(decoded.first { $0.name == "error-one" })

        #expect(failed.user == "tester")
        #expect(failed.exitCode == 1)
    }

    // MARK: - SM2 — detail

    @Test("Null optional info keys decode as absent")
    func nullOptionalInfoKeysDecodeAsAbsent() throws {
        let detail = try detail(ServicesFixture.infoWithNullOptionalKeys)

        #expect(detail.logPaths.isEmpty, "a null log path became a placeholder")
        #expect(detail.pid == nil)
        #expect(detail.user == nil)
        // Everything that was present is still present.
        #expect(detail.name == "atuin")
        #expect(detail.status == .none)
        #expect(detail.plistPath?.path == "/opt/homebrew/opt/atuin/homebrew.mxcl.atuin.plist")
    }

    @Test("Identical log and error-log paths are presented once")
    func identicalLogAndErrorLogPathsArePresentedOnce() throws {
        let same = try detail(ServicesFixture.infoWithIdenticalLogPaths)

        #expect(same.logPaths.count == 1, "one file was offered as two locations")
        #expect(same.logPaths.map(\.path) == ["/opt/homebrew/var/log/atuin.log"])

        let distinct = try detail(ServicesFixture.infoWithDistinctLogPaths)

        // Order-stable: the ordinary log first, the error log second.
        #expect(distinct.logPaths.map(\.path) == [
            "/opt/homebrew/var/log/atuin.log",
            "/opt/homebrew/var/log/atuin.error.log"
        ])
        #expect(distinct.pid == 4242)
        #expect(distinct.user == "tester")
    }

    /// A service with only an error log declares one location, not a blank
    /// first slot followed by it.
    @Test("A service declaring only an error log presents exactly that one")
    func aServiceDeclaringOnlyAnErrorLogPresentsExactlyThatOne() throws {
        let detail = try detail(
            ServicesFixture.info(
                name: "atuin",
                logPath: "null",
                errorLogPath: "\"/opt/homebrew/var/log/atuin.error.log\""
            )
        )

        #expect(detail.logPaths.map(\.path) == ["/opt/homebrew/var/log/atuin.error.log"])
    }
}
