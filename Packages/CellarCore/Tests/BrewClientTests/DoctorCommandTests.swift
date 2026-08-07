import BrewProcess
import Foundation
import Testing

@testable import BrewClient

/// The one `brew` invocation this capability makes (`system-health`, "Doctor is
/// a read, and running it fixes nothing"; design HD1).
///
/// Two threat rows meet in this file. **Argument composition**: the vector is a
/// compile-time constant with exactly one element, so no package name, selection,
/// catalog record or user string can reach it — there is no parameter to reach it
/// *through*. **Subprocess integration**: `.read` is not a convenience. `brew
/// doctor` changes nothing (U14 measured the fetch marker's modification date
/// identical either side of two runs under `HOMEBREW_NO_AUTO_UPDATE=1`), so
/// classifying it as a mutation would serialise a harmless measurement behind
/// every install in the queue and write a history entry for a command that did
/// nothing.
@Suite("Doctor command")
struct DoctorCommandTests {

    // MARK: - TM2 — argument composition

    @Test("The doctor argv is exactly one element, and that element is `doctor`")
    func theArgvIsExactlyDoctor() {
        #expect(DoctorCommand.command.arguments == ["doctor"])
        #expect(DoctorCommand.command.arguments.count == 1)
    }

    /// `--fix` does not exist in brew, and `--list-checks` was deliberately
    /// deferred (D5). Neither may appear by accident through a later "small"
    /// addition, and no flag may arrive at all.
    @Test("No flag, no name and no second element can appear in the vector")
    func theVectorCarriesNothingElse() {
        let arguments = DoctorCommand.command.arguments

        #expect(arguments.allSatisfy { $0.hasPrefix("-") == false }, "a flag entered the doctor argv")
        for forbidden in ["--fix", "--list-checks", "--verbose", "--debug", "-d"] {
            #expect(arguments.contains(forbidden) == false, "\(forbidden) entered the doctor argv")
        }
    }

    /// The structural half of the same claim: the declaration itself has no
    /// parameter, no interpolation and no joining, so there is no code path that
    /// could put a user string in the vector even if a caller wanted to.
    ///
    /// Asserted over the declarations rather than the prose — the reasoning is
    /// worth a comment, and a comment cannot build an argv.
    @Test("The declaration takes no parameter, interpolates nothing and joins nothing")
    func theDeclarationHasNoWayToAcceptAString() throws {
        let source = try Self.declarations(of: "DoctorCommand.swift")

        #expect(source.contains("[\"doctor\"]"), "the literal vector is gone")
        #expect(source.contains("BrewCommand.read("), "the command is no longer read-classified")
        #expect(source.contains("\\(") == false, "the doctor command interpolates a value into argv")
        #expect(source.contains(".joined(") == false, "the doctor command joins its argv")
        #expect(source.contains("func ") == false, "the doctor command exposes a function that could take a name")
        #expect(source.contains("init(") == false, "the doctor command offers an initialiser to pass a name to")

        // `arguments` is a **computed literal**, not a stored `String`: there is
        // nothing to assign to and nothing to vary. The earlier form of this
        // assertion banned `var` outright, which would have forced the vector to
        // hide behind a differently named constant and exempted this file from
        // the shipped `*Command.swift` argv guard in `MutationCommandTests`.
        #expect(source.contains("static var arguments: [String] { [\"doctor\"] }"))
        let storedStrings = source
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("var ") || ($0.contains("let ") && $0.contains("String")) }
        #expect(storedStrings.isEmpty, "the doctor command stores \(storedStrings)")

        // `/bin/sh -c` is never how anything in this package runs, and this file
        // is the newest opportunity to start.
        #expect(source.contains("/bin/sh") == false)
        #expect(source.contains("-c\"") == false)
    }

    // MARK: - TM1, SH4 — doctor is a read

    @Test("Doctor is classified as a read, so it bypasses the mutation gate")
    func doctorIsARead() {
        #expect(DoctorCommand.command.kind == .read)
        #expect(DoctorCommand.command.kind != .mutate)
    }

    /// The environment pin the capture was taken under is the one the command
    /// carries: asking how healthy Homebrew is must not be what updates it.
    @Test("The command adds no environment override that could permit an update")
    func theCommandPermitsNoUpdate() {
        // Whatever overrides exist, none of them may re-enable auto-update.
        for override in DoctorCommand.command.environmentOverrides {
            #expect(
                String(describing: override).lowercased().contains("autoupdate") == false,
                "the doctor command carries an auto-update override"
            )
        }
    }

    /// The file with every comment line removed, so a structural claim is made
    /// about what the module *declares* rather than about what it explains.
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
