import BrewProcess
import Foundation
import Testing

@testable import BrewClient

/// The doctor seam, and the inversion its **signature** enforces (`system-health`,
/// "A non-zero doctor exit is an ordinary outcome, and the document arrives on
/// stderr"; design HD1).
///
/// `DoctorSourcing.run(using:)` has no `throws` at all. That is not a stylistic
/// preference: it is what makes "brew found warnings" unable to be reported as a
/// failure. A `throws(DoctorError)` variant would keep non-zero-as-error
/// *expressible*, so a later "simplification" back onto the three JSON payload
/// sources' rule would compile. This one cannot.
///
/// Every launcher here is **per-instance**. There is no shared counter and no
/// `install()`-style reset anywhere in this file.
@Suite("Doctor source")
struct DoctorSourceTests {
    private static let report = """
    Please note that these warnings are just used to help the Homebrew maintainers

    Warning: Some installed formulae are deprecated or disabled.
      ruby@3.1

    """

    private static func run(
        stdout: String = "\n",
        stderr: String = report,
        exit: BrewExit
    ) -> ScriptedRun {
        ScriptedRun(stdout: stdout, stderr: stderr, exit: exit)
    }

    // MARK: - 3.1 — the three outcomes, and the inversion

    @Test("A non-zero exit carrying a report is `issues`, not a failure")
    func aNonZeroExitIsAnOrdinaryOutcome() async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: 1, reason: .exited))
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        guard case .issues(let evidence) = outcome else {
            Issue.record("a warnings run produced \(outcome) rather than .issues")
            return
        }
        #expect(evidence.warningCount == 1)
        #expect(evidence.warnings[0].headline == "Some installed formulae are deprecated or disabled.")
        #expect(evidence.isPartial == false, "an ordinary warnings run was reported partial")
    }

    @Test("An exit of zero over the ready sentence is `clean`")
    func anExitOfZeroIsClean() async {
        let launcher = RecordingProcessLauncher([
            Self.run(
                stdout: "Your system is ready to brew.\n",
                stderr: "",
                exit: BrewExit(status: 0, reason: .exited)
            )
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        guard case .clean(let evidence) = outcome else {
            Issue.record("a clean run produced \(outcome) rather than .clean")
            return
        }
        #expect(evidence.warningCount == 0)
        #expect(evidence.unknownLineCount == 0)
        #expect(evidence.reportsReady)
    }

    @Test("A cancelled run is unavailable, naming cancellation")
    func aCancelledRunIsUnavailable() async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: 128 + SIGINT, reason: .cancelled(signal: SIGINT)))
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        #expect(outcome == .unavailable(.cancelled))
        #expect(outcome.evidence == nil)
    }

    @Test("A run terminated by a signal Cellar did not send is unavailable, not a partial report")
    func aSignalledRunIsUnavailable() async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: 128 + SIGKILL, reason: .signalled(SIGKILL)))
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        #expect(outcome == .unavailable(.signalled(SIGKILL)))
    }

    @Test("A spawn failure is unavailable, naming the fault")
    func aSpawnFailureIsUnavailable() async {
        let url = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let launcher = RecordingProcessLauncher(failingWith: BrewProcessError.executableUnavailable(url))

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        #expect(outcome == .unavailable(.brewUnavailable))
        #expect(outcome.evidence == nil)
    }

    /// The whole inversion, stated as the one thing that must never happen: a
    /// run that **completed** can never be unavailable, whatever it exited with.
    @Test(
        "A completed run never reaches `unavailable`, at any exit status",
        arguments: [Int32(0), 1, 2, 42, 127, 255]
    )
    func aCompletedRunIsNeverUnavailable(status: Int32) async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: status, reason: .exited))
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        if case .unavailable(let reason) = outcome {
            Issue.record("a completed run with status \(status) reported unavailable(\(reason))")
            return
        }
        // And it carries the document either way.
        #expect(outcome.evidence != nil)
        #expect(outcome.evidence?.rawStderr == Data(Self.report.utf8))
    }

    /// The signature is the enforcement. `run(using:)` is `async` and **not**
    /// `throws`, so "brew found warnings" has no way to become an error even if
    /// somebody wanted it to.
    @Test("The seam cannot throw at all")
    func theSeamCannotThrow() throws {
        let source = try Self.declarations(of: "DoctorSource.swift")

        #expect(source.contains("func run(using installation: BrewInstallation) async -> DoctorOutcome"))
        #expect(source.contains("throws") == false, "the doctor seam can throw")
        // And the protocol it conforms to declares the same shape.
        #expect(source.contains("protocol DoctorSourcing: Sendable"))

        // The file does contain `try`, and that is the design rather than a
        // leak: the spawn fault is the one thing that can throw, and it is
        // **converted** into an outcome rather than propagated. Asserting "no
        // `try` anywhere" would have banned the conversion itself, so the
        // assertion is that the conversion is present and that no `try`
        // suspends across an await where it could escape.
        #expect(
            source.contains("return .unavailable(Self.spawnFailure("),
            "the spawn fault is no longer converted into an outcome"
        )
        #expect(source.contains("try await") == false, "an awaited throw can escape the doctor seam")
        #expect(source.contains("try? process.send(.interrupt)"), "cancellation stopped being best-effort")
    }

    // MARK: - 3.2 — stderr is the document, and the streams stay apart

    @Test("The document is read from stderr, and a newline-only stdout is not malformed")
    func theDocumentIsReadFromStderr() async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: 1, reason: .exited))
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        let evidence = try? #require(outcome.evidence)
        #expect(evidence?.rawStdout == Data("\n".utf8))
        #expect(evidence?.warningCount == 1, "a newline-only stdout was refused as blank or malformed")
        #expect(evidence?.provenance.documentStream == .stderr)
    }

    @Test("Both raw streams reach the evidence separately and unconcatenated")
    func bothRawStreamsReachTheEvidenceSeparately() async {
        let launcher = RecordingProcessLauncher([
            Self.run(stdout: "\n", stderr: Self.report, exit: BrewExit(status: 1, reason: .exited))
        ])

        let outcome = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)
        let evidence = try? #require(outcome.evidence)

        let stdout = Data("\n".utf8)
        let stderr = Data(Self.report.utf8)
        #expect(evidence?.rawStdout == stdout)
        #expect(evidence?.rawStderr == stderr)
        #expect(evidence?.rawStdout != stdout + stderr)
        #expect(evidence?.rawStderr != stdout + stderr)
        #expect(evidence?.rawStderr != stderr + stdout)
    }

    /// Exactly three outcomes exist, and `unavailable` covers only the
    /// no-document-at-all cases. Enumerated exhaustively so a fourth case, or a
    /// widened `unavailable`, fails here.
    @Test("Exactly three typed outcomes exist, and unavailable names only an absent answer")
    func exactlyThreeOutcomesExist() async {
        let warnings = await BrewDoctorSource(
            launcher: RecordingProcessLauncher([Self.run(exit: BrewExit(status: 1, reason: .exited))])
        ).run(using: TestInstallation.appleSilicon)
        let clean = await BrewDoctorSource(
            launcher: RecordingProcessLauncher([
                Self.run(stdout: "Your system is ready to brew.\n", stderr: "",
                         exit: BrewExit(status: 0, reason: .exited))
            ])
        ).run(using: TestInstallation.appleSilicon)
        let absent = await BrewDoctorSource(
            launcher: RecordingProcessLauncher(
                failingWith: BrewProcessError.launchFailed(URL(fileURLWithPath: "/x"), code: 13)
            )
        ).run(using: TestInstallation.appleSilicon)

        // Each of the three is reachable, and each is a different one.
        var seen: Set<String> = []
        for outcome in [warnings, clean, absent] {
            switch outcome {
            case .issues: seen.insert("issues")
            case .clean: seen.insert("clean")
            case .unavailable: seen.insert("unavailable")
            }
        }
        #expect(seen == ["issues", "clean", "unavailable"])

        // Only the third carries no document.
        #expect(warnings.evidence != nil)
        #expect(clean.evidence != nil)
        #expect(absent.evidence == nil)
    }

    // MARK: - 3.4, SH4/TM1 — doctor is a read and changes nothing

    @Test("The run spawns exactly one process, with exactly the doctor argv")
    func theRunSpawnsExactlyTheDoctorArgv() async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: 1, reason: .exited))
        ])

        _ = await BrewDoctorSource(launcher: launcher).run(using: TestInstallation.appleSilicon)

        #expect(launcher.launchCount == 1, "a doctor run spawned \(launcher.launchCount) processes")
        #expect(launcher.specs.map(\.arguments) == [["doctor"]])
        #expect(launcher.specs[0].executableURL == TestInstallation.appleSilicon.executableURL)
    }

    /// Two runs, and still nothing but doctor: no `update`, no `info`, no
    /// re-snapshot chased on the back of a measurement.
    @Test("Two doctor runs spawn two doctor processes and nothing else at all")
    func twoRunsSpawnNothingButDoctor() async {
        let launcher = RecordingProcessLauncher([
            Self.run(exit: BrewExit(status: 1, reason: .exited))
        ])
        let source = BrewDoctorSource(launcher: launcher)

        _ = await source.run(using: TestInstallation.appleSilicon)
        _ = await source.run(using: TestInstallation.appleSilicon)

        #expect(launcher.launchCount == 2)
        #expect(Set(launcher.specs.map(\.arguments)) == [["doctor"]])
        for spec in launcher.specs {
            for forbidden in ["update", "upgrade", "install", "uninstall", "cleanup", "autoremove"] {
                #expect(spec.arguments.contains(forbidden) == false, "a doctor run issued \(forbidden)")
            }
        }
    }

    /// The read classification, which is what U14 measured the consequence of:
    /// the fetch marker's modification date was identical before and after two
    /// doctor runs under `HOMEBREW_NO_AUTO_UPDATE=1`, re-measured during apply on
    /// 2026-08-07. A `.mutate` classification would serialise this behind the
    /// queue *and* write a history entry for a command that changed nothing.
    @Test("The command the source issues is the read-classified constant")
    func theSourceIssuesTheReadClassifiedConstant() {
        #expect(DoctorCommand.command.kind == .read)
        #expect(DoctorCommand.command.arguments == ["doctor"])
    }

    /// The structural half: the source has no way to submit a mutation, write a
    /// history entry, or invalidate installed state, because it names none of
    /// those types. Its only collaborator is the process seam.
    @Test("The source names no operation queue, history store or installed state")
    func theSourceNamesNoSpineCollaborator() throws {
        let source = try Self.declarations(of: "DoctorSource.swift")

        for forbidden in [
            "OperationCenter", "HistoryRecording", "HistoryStore", "InstalledStore",
            "MutationCommand", "BrewMutating", "invalidate", "MetadataStore", "refresh"
        ] {
            #expect(source.contains(forbidden) == false, "the doctor source reaches \(forbidden)")
        }
        // Positive anchor: the scan is reading a real file with real content.
        #expect(source.contains("ProcessLaunching"), "the source scan read nothing")
        #expect(source.contains("DoctorCommand.command"))
    }

    private static func declarations(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
    }
}
