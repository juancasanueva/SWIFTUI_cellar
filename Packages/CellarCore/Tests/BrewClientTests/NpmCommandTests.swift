import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The two npm mutations, their fixed argv vectors and the validated token the
/// upgrade is spelled with (`npm-source` — "npm commands are a separate family
/// with fixed argv vectors and validated names"; design D14).
@Suite("npm command family")
struct NpmCommandTests {
    private static let typescript = PackageID(kind: .npm, name: "typescript")
    private static let scoped = PackageID(kind: .npm, name: "@angular/cli")

    // MARK: - Argv exactness

    @Test("Upgrade and uninstall lower to exactly their two fixed vectors")
    func argvVectorsAreExact() throws {
        let target = try #require(NpmPackageTarget(Self.typescript))

        #expect(NpmCommand.upgrade(target).arguments == ["install", "-g", "typescript@latest"])
        #expect(NpmCommand.uninstall(target).arguments == ["uninstall", "-g", "typescript"])
    }

    /// The spec token is **one argv element**, which is the whole reason it is
    /// built in the wrapper rather than interpolated where the vector is
    /// assembled: a name and a version separated by a space would be two
    /// packages to npm, and `typescript@latest` as three elements would be a
    /// syntax error rather than a refusal.
    @Test("The latest spec is a single argv element built once in the wrapper")
    func latestSpecIsOneElement() throws {
        let target = try #require(NpmPackageTarget(Self.typescript))

        #expect(target.latestSpec == "typescript@latest")
        let arguments = NpmCommand.upgrade(target).arguments
        #expect(arguments.count == 3)
        #expect(arguments[2] == target.latestSpec)
        #expect(arguments.contains { $0.contains(" ") } == false)
    }

    /// Triangulation: a scoped name is the shape whose `@` the validation rule
    /// exists to allow, and it survives into both vectors intact.
    @Test("A scoped name survives into both vectors intact")
    func scopedNameSurvives() throws {
        let target = try #require(NpmPackageTarget(Self.scoped))

        #expect(target.name == "@angular/cli")
        #expect(target.latestSpec == "@angular/cli@latest")
        #expect(NpmCommand.upgrade(target).arguments == ["install", "-g", "@angular/cli@latest"])
        #expect(NpmCommand.uninstall(target).arguments == ["uninstall", "-g", "@angular/cli"])
    }

    // MARK: - Refusal at construction

    @Test(
        "Hostile names are rejected at construction and produce no argv",
        arguments: ["", " ", "--force", "typescript@5", "a b", "-g", "@angular/cli@1"]
    )
    func hostileNamesAreRejected(name: String) {
        #expect(NpmPackageTarget(PackageID(kind: .npm, name: name)) == nil)
    }

    @Test("A Homebrew identity can never become an npm target")
    func homebrewIdentityIsNotAnNpmTarget() {
        #expect(NpmPackageTarget(PackageID(kind: .formula, name: "wget")) == nil)
        #expect(NpmPackageTarget(PackageID(kind: .cask, name: "iterm2")) == nil)
    }

    // MARK: - The other direction: no brew argv ever names an npm package

    /// `package-mutation`: "A brew verb is unavailable for an npm identity" —
    /// construction fails and every verb reports unavailable, so
    /// `MutationCommand.vector`'s npm arm is unreachable by construction rather
    /// than merely untaken.
    @Test("Every brew package verb is unavailable for an npm identity")
    func brewVerbsAreUnavailableForNpm() {
        let npm = Self.typescript

        #expect(PackageTarget(npm) == nil)
        #expect(FormulaID(npm) == nil)
        #expect(CaskID(npm) == nil)

        let built: [MutationCommand?] = [
            MutationCommand.naming(npm, MutationCommand.install),
            MutationCommand.naming(npm, MutationCommand.uninstall),
            MutationCommand.naming(npm, MutationCommand.reinstall),
            MutationCommand.naming(npm, MutationCommand.upgrade),
            FormulaID(npm).map(MutationCommand.pin),
            FormulaID(npm).map(MutationCommand.unpin),
        ]
        #expect(built.count == 6)
        #expect(built.allSatisfy { $0 == nil })
        #expect(built.compactMap { $0 }.flatMap(\.arguments).contains("typescript") == false)
    }

    // MARK: - Spine projections

    @Test("The npm family declares the npm inventory domain and nothing else")
    func npmCommandsDeclareOnlyTheNpmDomain() throws {
        let target = try #require(NpmPackageTarget(Self.typescript))

        for command in [NpmCommand.upgrade(target), .uninstall(target)] {
            #expect(command.invalidates == .npmInventory)
            #expect(command.invalidates.contains(.installedInventory) == false)
            #expect(command.diskAreas.isEmpty)
            #expect(command.source == .npm)
            #expect(command.packageID == Self.typescript)
        }
    }

    @Test("Uninstall requires confirmation and upgrade does not")
    func onlyUninstallConfirms() throws {
        let target = try #require(NpmPackageTarget(Self.typescript))

        #expect(NpmCommand.uninstall(target).requiresConfirmation)
        #expect(NpmCommand.uninstall(target).disclosure == .packageRemoval)
        #expect(NpmCommand.upgrade(target).requiresConfirmation == false)
    }

    /// The two namespaced verbs the durable record is written and searched under
    /// (`installation-history` — npm entries store namespaced verbs).
    @Test("The two verbs are namespaced so an npm row is never a brew row")
    func verbsAreNamespaced() throws {
        let target = try #require(NpmPackageTarget(Self.typescript))

        #expect(NpmCommand.upgrade(target).verb == "npmUpgrade")
        #expect(NpmCommand.uninstall(target).verb == "npmUninstall")
    }

    // MARK: - The structural scan, extended to this file

    /// `npm-source`: "The command file MUST sit at the top level of the command
    /// sources so the shipped structural argv scan covers it."
    ///
    /// Asserted here as a **membership** claim; the rule itself is enforced by
    /// `MutationCommandTests.everyCommandFamilyBuildsArgvStructurally`, which
    /// globs the same directory. Anchored positively so a wrong path cannot make
    /// it pass vacuously.
    @Test("The npm command file is covered by the shipped structural argv scan")
    func npmCommandFileIsScanned() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrewClient")
        let scanned = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix("Command.swift") }

        #expect(scanned.contains("MutationCommand.swift"), "the glob is wrong")
        #expect(scanned.contains("NpmCommand.swift"), "the npm family is outside the scanned set")

        let source = try String(
            contentsOf: directory.appendingPathComponent("NpmCommand.swift"),
            encoding: .utf8
        )
        #expect(source.contains("MutationName.isSafe"))
        let start = try #require(source.range(of: "var arguments: [String]"))
        let rest = source[start.upperBound...]
        let body = rest.range(of: "\n    }").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        #expect(body.contains("["))
        for construct in ["\\(", "joined(", "components(separatedBy:", "split(", "+ \" \""] {
            #expect(body.contains(construct) == false, "the npm argv body uses \(construct)")
        }
    }
}
