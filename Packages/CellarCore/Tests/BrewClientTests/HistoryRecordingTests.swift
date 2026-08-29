import BrewProcess
import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The seam between a terminal outcome and the durable record it owes
/// (design D7, installation-history IH7).
@Suite("History recording")
struct HistoryRecordingTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    private static func draft(
        packageID: PackageID? = wget,
        verb: String = "install",
        versions: VersionTransition? = nil,
        outcome: MutationOutcome = .succeeded,
        argv: [String] = ["install", "--formula", "wget"]
    ) -> HistoryDraft {
        HistoryDraft(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_000),
            packageID: packageID,
            verb: verb,
            versions: versions,
            outcome: outcome,
            argv: argv
        )
    }

    // MARK: - The no-op default

    @Test("NoHistoryRecording accepts a draft and does nothing")
    @MainActor
    func theDefaultRecorderDoesNothing() {
        let recorder = NoHistoryRecording()

        recorder.record(Self.draft())
        recorder.record(Self.draft(verb: "uninstall"))

        // Nothing to observe is the whole point: it is the seam's identity
        // element, so `OperationCenter` behaves exactly as it did in M2-2 when
        // no recorder is configured (IH7 sc1).
        #expect(recorder is any HistoryRecording)
    }

    // MARK: - The draft carries what a row needs

    @Test("A draft carries the package, the verb, the transition, the outcome and the argv")
    func aDraftCarriesEverythingARowNeeds() throws {
        let draft = Self.draft(
            versions: VersionTransition(from: "1.2.2", to: "1.2.3"),
            argv: ["upgrade", "--formula", "wget"]
        )

        #expect(draft.packageID == Self.wget)
        #expect(draft.verb == "install")
        #expect(draft.outcome == .succeeded)
        #expect(draft.argv == ["upgrade", "--formula", "wget"])
        #expect(draft.commandText == "upgrade --formula wget")

        let versions = try #require(draft.versions)
        #expect(versions.from == "1.2.2")
        #expect(versions.to == "1.2.3")
    }

    /// `nil` means the entry names no package — an `upgradeAll`, which is
    /// recorded as one grouped entry (settled R1, IH2 sc1).
    @Test("A draft with no package identity is the grouped upgrade-all shape")
    func aGroupedDraftNamesNoPackage() {
        let draft = Self.draft(
            packageID: nil,
            verb: "upgradeAll",
            argv: ["upgrade"]
        )

        #expect(draft.packageID == nil)
        #expect(draft.commandText == "upgrade")
        #expect(draft.verb == "upgradeAll")
        #expect(draft.versions == nil)
    }

    // MARK: - The failure tail

    /// Only `.failed` keeps log lines: its own doc says "the log is the
    /// explanation", while every other outcome already names its cause. The
    /// tail is verbatim, display-only, and bounded to the newest lines.
    @Test("Only a plain failure carries a log tail, capped to the newest lines")
    func onlyAFailureCarriesABoundedTail() {
        let log = (0..<30).map {
            LogLine(stream: $0.isMultiple(of: 2) ? .stdout : .stderr, text: "line \($0)", sequence: $0)
        }

        let tail = HistoryDraft.failureTail(of: log, for: .failed(status: 1))
        #expect(tail.count == HistoryDraft.failureTailLimit)
        #expect(tail.first == "line \(30 - HistoryDraft.failureTailLimit)")
        #expect(tail.last == "line 29")

        #expect(HistoryDraft.failureTail(of: log, for: .succeeded).isEmpty)
        #expect(HistoryDraft.failureTail(of: log, for: .cancelled).isEmpty)
        #expect(HistoryDraft.failureTail(of: log, for: .needsPrivileges).isEmpty)
        #expect(HistoryDraft.failureTail(of: [], for: .failed(status: 1)).isEmpty)
    }

    @Test("A transition is only carried when both ends are known")
    func aTransitionNeedsBothEnds() {
        #expect(VersionTransition(from: "1.2.2", to: "1.2.3") != nil)
        #expect(VersionTransition(from: "", to: "1.2.3") == nil)
        #expect(VersionTransition(from: "1.2.2", to: "") == nil)
        #expect(VersionTransition(from: "", to: "") == nil)
    }

    // MARK: - IH7 — a recording failure can never change an outcome

    /// The protocol is `@MainActor`, **synchronous and non-throwing**, so a
    /// failed write is not something a mutation's terminal path can observe at
    /// all. Asserted structurally, because "it does not throw today" is a
    /// property of the signature rather than of the current implementation.
    @Test("The recording protocol is synchronous and non-throwing by signature")
    func theProtocolCannotFailIntoAnOperation() throws {
        let source = try Self.source(of: "HistoryRecording.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let marker = line.range(of: "//") else { return line }
                return line[line.startIndex..<marker.lowerBound]
            }
            .joined(separator: "\n")

        let declaration = try #require(
            source.components(separatedBy: "protocol HistoryRecording").last?
                .components(separatedBy: "}").first
        )
        #expect(declaration.contains("func record(_ draft: HistoryDraft)"))
        #expect(declaration.contains("throws") == false, "the recorder can throw into an operation")
        #expect(declaration.contains("async") == false, "the recorder can suspend a terminal path")
        #expect(source.contains("@MainActor public protocol HistoryRecording"))
    }

    /// A recorder that fails on every write is indistinguishable, from the
    /// caller's side, from one that succeeds.
    @Test("A recorder that fails on every write still accepts every draft")
    @MainActor
    func aFailingRecorderStillAcceptsDrafts() {
        let recorder = FailingHistoryRecorder()

        recorder.record(Self.draft())
        recorder.record(Self.draft(verb: "uninstall"))

        #expect(recorder.attempted == 2, "a failing recorder stopped accepting drafts")
        #expect(recorder.stored.isEmpty)
    }

    // MARK: -

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
    }
}

/// Records every draft it is handed, in order.
@MainActor
final class RecordingHistoryRecorder: HistoryRecording {
    private(set) var drafts: [HistoryDraft] = []

    func record(_ draft: HistoryDraft) {
        drafts.append(draft)
    }
}

/// Fails every write, and remembers that it was asked.
@MainActor
final class FailingHistoryRecorder: HistoryRecording {
    private(set) var attempted = 0
    private(set) var stored: [HistoryDraft] = []

    func record(_ draft: HistoryDraft) {
        attempted += 1
        // The write "fails": nothing is stored, and nothing is reported back.
    }
}
