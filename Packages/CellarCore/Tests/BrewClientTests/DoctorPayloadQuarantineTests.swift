import BrewProcess
import Foundation
import Testing

@testable import BrewClient

/// The doctor payload rule is a **double inversion**, and this file is what keeps
/// it quarantined (`system-health`, "The doctor inversion is quarantined to this
/// capability"; design HD3, proposal binding invariant 1c).
///
/// `brew doctor` reports warnings by exiting `1` and writing its whole report to
/// **stderr**. The three shipped JSON payload sources require the exact opposite,
/// each for its own document reasons: a non-zero exit is an error, because brew
/// failing while printing `{"formulae":[],"casks":[]}` must not read as "the user
/// uninstalled everything"; and stderr never enters the document, at any
/// position, so a warning interleaved into the middle of the JSON cannot corrupt
/// it.
///
/// Both rules are correct. They are correct about **different documents**. The
/// danger is not that either is wrong — it is that one of them spreads.
///
/// So this suite asserts **both halves**, behaviourally:
///
/// - the trio still refuses a non-zero exit, and still admits stdout only;
/// - the doctor source still accepts a non-zero exit, and still reads stderr.
///
/// A "simplification" in **either** direction fails a test here rather than a
/// review. It is deliberately behavioural rather than a text scan, so it holds
/// even if all four files are refactored — and it is why
/// `openspec/specs/brew-execution/spec.md` is a 0-line diff (decision D7): the
/// licence is recorded in the new capability's Provenance, not by editing a
/// shipped main spec.
@Suite("Doctor payload quarantine")
struct DoctorPayloadQuarantineTests {

    /// The three shipped JSON sources, each reduced to "decode this run".
    ///
    /// Named rather than parameterised over a protocol because they have three
    /// different closed error types — which is itself part of the point: no
    /// shared template exists for a relaxation to be applied to *once*.
    enum JSONSource: String, CaseIterable, CustomStringConvertible {
        case installed, services, taps

        var description: String { rawValue }

        /// The well-formed document each one expects, so a refusal below is
        /// never a refusal of malformed JSON.
        var document: String {
            switch self {
            case .installed: "{\"formulae\":[],\"casks\":[]}"
            case .services: "[]"
            case .taps: "[]"
            }
        }
    }

    private static func lines(stdout: [String] = [], stderr: [String] = []) -> [LogLine] {
        var lines: [LogLine] = []
        for text in stdout {
            lines.append(LogLine(stream: .stdout, text: text, sequence: lines.count))
        }
        for text in stderr {
            lines.append(LogLine(stream: .stderr, text: text, sequence: lines.count))
        }
        return lines
    }

    /// What each source did with a run. `nil` means it returned a document.
    private static func refusal(
        _ source: JSONSource,
        lines: [LogLine],
        exit: BrewExit
    ) -> (isCommandFailure: Bool, isAbsentOrMalformed: Bool, returnedDocument: Data?) {
        switch source {
        case .installed:
            do {
                return (false, false, try InstalledPayload.payload(from: lines, exit: exit))
            } catch {
                return (
                    { if case .commandFailed = error { true } else { false } }(),
                    error == .malformedPayload,
                    nil
                )
            }
        case .services:
            do {
                return (false, false, try ServicesPayload.payload(from: lines, exit: exit))
            } catch {
                return (
                    { if case .commandFailed = error { true } else { false } }(),
                    error == .malformedPayload,
                    nil
                )
            }
        case .taps:
            do {
                return (false, false, try TapPayload.payload(from: lines, exit: exit))
            } catch {
                return (
                    { if case .commandFailed = error { true } else { false } }(),
                    error == .blankOutput,
                    nil
                )
            }
        }
    }

    // MARK: - 4.1 — the trio still rejects a non-zero exit

    /// A non-zero exit **carrying a perfectly good document on stdout**. This is
    /// the exact shape the doctor rule would relax, so it is the exact shape that
    /// must still be refused.
    @Test(
        "A non-zero exit over a well-formed JSON body is still a command failure",
        arguments: JSONSource.allCases
    )
    func aNonZeroExitIsStillACommandFailure(source: JSONSource) {
        let outcome = Self.refusal(
            source,
            lines: Self.lines(stdout: [source.document], stderr: ["Error: something went wrong"]),
            exit: BrewExit(status: 1, reason: .exited)
        )

        #expect(outcome.isCommandFailure, "\(source) admitted a non-zero exit")
        #expect(outcome.returnedDocument == nil, "\(source) returned a document from a failed run")
    }

    /// And at every non-zero status, not just `1` — a relaxation that special-cased
    /// "doctor's status" would otherwise slip through.
    @Test(
        "No non-zero status is admitted by any of the three",
        arguments: JSONSource.allCases, [Int32(1), 2, 42, 127]
    )
    func noNonZeroStatusIsAdmitted(source: JSONSource, status: Int32) {
        let outcome = Self.refusal(
            source,
            lines: Self.lines(stdout: [source.document]),
            exit: BrewExit(status: status, reason: .exited)
        )

        #expect(outcome.isCommandFailure, "\(source) admitted status \(status)")
        #expect(outcome.returnedDocument == nil)
    }

    /// The control that keeps the two tests above meaningful: at exit `0` with
    /// the document on stdout, each source **does** return it. Without this, the
    /// refusals could be a source that refuses everything.
    @Test("At exit 0 with the document on stdout, each source returns it", arguments: JSONSource.allCases)
    func theHappyPathStillReturnsTheDocument(source: JSONSource) {
        let outcome = Self.refusal(
            source,
            lines: Self.lines(stdout: [source.document]),
            exit: BrewExit(status: 0, reason: .exited)
        )

        #expect(outcome.returnedDocument == Data(source.document.utf8), "\(source) refuses its own happy path")
        #expect(outcome.isCommandFailure == false)
    }

    // MARK: - 4.2 — the trio still admits stdout only

    /// The other direction: exit `0`, blank stdout, the document on **stderr**.
    /// This is the shape `brew doctor` actually produces, and the trio must still
    /// treat it as no document at all.
    @Test(
        "An exit-0 run with the body on stderr is still absent or malformed",
        arguments: JSONSource.allCases
    )
    func aDocumentOnStderrIsStillNoDocument(source: JSONSource) {
        let outcome = Self.refusal(
            source,
            lines: Self.lines(stdout: [""], stderr: [source.document]),
            exit: BrewExit(status: 0, reason: .exited)
        )

        #expect(outcome.isAbsentOrMalformed, "\(source) accepted a document that arrived on stderr")
        #expect(outcome.returnedDocument == nil)
        #expect(outcome.isCommandFailure == false, "\(source) reported the wrong reason")
    }

    /// And stderr does not leak into the document even when stdout has content
    /// of its own — the "at any position" half of the rule.
    @Test("stderr never joins a document that stdout did produce", arguments: JSONSource.allCases)
    func stderrNeverJoinsTheDocument(source: JSONSource) {
        let outcome = Self.refusal(
            source,
            lines: Self.lines(
                stdout: [source.document],
                stderr: ["Warning: an unrelated diagnostic"]
            ),
            exit: BrewExit(status: 0, reason: .exited)
        )

        let document = try? #require(outcome.returnedDocument)
        #expect(document == Data(source.document.utf8))
        #expect(
            String(decoding: document ?? Data(), as: UTF8.self).contains("unrelated diagnostic") == false,
            "\(source) folded stderr into its document"
        )
    }

    // MARK: - 4.3 — both halves, so a simplification in either direction fails

    /// The trio's two refusals and doctor's two acceptances, asserted together.
    ///
    /// Together is the point. Asserting only the trio would pass if doctor were
    /// "fixed" to match them; asserting only doctor would pass if the trio were
    /// relaxed to match doctor. Both in one test means the *divergence* is what
    /// is pinned, not either side of it.
    @Test("The trio refuses exactly what doctor accepts, and both are asserted here")
    func theTrioRefusesExactlyWhatDoctorAccepts() async {
        // Half one: the trio, on both shapes.
        for source in JSONSource.allCases {
            let nonZero = Self.refusal(
                source,
                lines: Self.lines(stdout: [source.document]),
                exit: BrewExit(status: 1, reason: .exited)
            )
            let onStderr = Self.refusal(
                source,
                lines: Self.lines(stdout: [""], stderr: [source.document]),
                exit: BrewExit(status: 0, reason: .exited)
            )
            #expect(nonZero.isCommandFailure, "\(source) stopped refusing a non-zero exit")
            #expect(onStderr.isAbsentOrMalformed, "\(source) started reading stderr")
        }

        // Half two: doctor, on the same two shapes, accepting both.
        let report = "Warning: something is off\n  and here is why\n"
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: "\n", stderr: report, exit: BrewExit(status: 1, reason: .exited))
        ])
        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        guard case .issues(let evidence) = outcome else {
            Issue.record("the doctor source stopped accepting a non-zero exit: \(outcome)")
            return
        }
        #expect(evidence.warningCount == 1, "the doctor source stopped reading stderr as the document")
        #expect(evidence.provenance.documentStream == .stderr)
        #expect(evidence.rawStdout == Data("\n".utf8), "the doctor source refused a newline-only stdout")
    }

    /// The four claims above, restated as the two sentences that must stay
    /// *false* of each other's subject. Cheap, and it is the sentence a future
    /// reader is most likely to try to make true.
    @Test("Neither rule has been unified with the other")
    func neitherRuleHasBeenUnified() async {
        // The doctor source would fail this if it had been re-derived from the
        // trio's template: it would have thrown, or returned nothing, on a
        // non-zero exit.
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: "", stderr: "Warning: x\n", exit: BrewExit(status: 1, reason: .exited))
        ])
        let doctor = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)
        #expect(doctor.evidence != nil, "doctor produced no document from a non-zero exit")

        // And the trio would fail this if the doctor relaxation had spread: each
        // returns nothing for the very same run shape.
        for source in JSONSource.allCases {
            let outcome = Self.refusal(
                source,
                lines: Self.lines(stderr: ["Warning: x"]),
                exit: BrewExit(status: 1, reason: .exited)
            )
            #expect(outcome.returnedDocument == nil, "\(source) produced a document from a doctor-shaped run")
        }
    }
}
