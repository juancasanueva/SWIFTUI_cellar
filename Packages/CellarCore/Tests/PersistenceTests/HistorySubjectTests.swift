import BrewClient
import Catalog
import Foundation
import Testing

@testable import Persistence

/// What a durable entry says it acted on (installation-history IH1).
///
/// Storage spells two different facts the same way: a grouped `upgradeAll` and
/// an operation with **no package identity at all** both persist `name == ""`
/// and `kindRaw == ""`. The empty string alone therefore cannot tell them
/// apart, and a projection that reads only `name` renders `brew services stop
/// atuin` as "All packages" — a false statement about what happened, and
/// exactly the synthesized identity IH1 forbids.
///
/// The verb can tell them apart, and these tests pin that it does. They are the
/// headless substitute for MV-7's "no package name rendered as a package
/// identity" half; the GUI half is still owed.
@Suite("History subject")
struct HistorySubjectTests {

    @Test("Tap denial outcome labels are presentation-ready without app-owned rules")
    func tapDenialLabelsAreProjectedInPersistence() {
        let changed = HistoryRecord(HistoryEntry(
            id: UUID(),
            date: Date(),
            kindRaw: "",
            name: "",
            verb: "tapForceUntap",
            versionFrom: "",
            versionTo: "",
            outcomeRaw: "authorizationDeniedEvidenceChanged",
            exitStatus: nil,
            argv: ["untap", "--force", "acme/tools"],
            commandText: "untap --force acme/tools"
        ))

        #expect(changed.subject == .noPackage)
        #expect(changed.outcomeLabel == "Needs fresh confirmation")
    }
    private static func record(
        name: String,
        kind: PackageKind? = nil,
        verb: String
    ) -> HistoryRecord {
        let argv = [verb, name].filter { !$0.isEmpty }
        return HistoryRecord(
            HistoryEntry(
                id: UUID(),
                date: Date(timeIntervalSince1970: 1_000),
                kindRaw: kind?.rawValue ?? "",
                name: name,
                verb: verb,
                versionFrom: "",
                versionTo: "",
                outcomeRaw: "succeeded",
                exitStatus: 0,
                argv: argv,
                commandText: argv.joined(separator: " ")
            )
        )
    }

    /// The four shipped service verbs, namespaced (design D9), read off the
    /// command family itself rather than retyped here.
    private static func serviceVerbs() throws -> [String] {
        let target = try #require(ServiceTarget(name: "atuin"))
        return ServiceCommand.allVerbs(for: target).map(\.verb)
    }

    // MARK: - The named case, unchanged

    @Test("An entry that names a package renders that package's name")
    func aNamedEntryRendersItsName() {
        let record = Self.record(name: "wget", kind: .formula, verb: "install")

        #expect(record.subject == .package("wget"))
        #expect(record.subject.label == "wget")
    }

    /// A row whose stored kind cannot be decoded still names its package: the
    /// name is what the user recognises, and `packageID` being `nil` here is a
    /// decoding degradation, not an absent identity.
    @Test("A named entry with an undecodable kind still renders its name")
    func aNamedEntryWithAnUndecodableKindStillRendersItsName() {
        let record = Self.record(name: "wget", verb: "install")

        #expect(record.packageID == nil)
        #expect(record.subject == .package("wget"))
        #expect(record.subject.label == "wget")
    }

    // MARK: - The grouped case

    @Test("A grouped upgrade names every package, and says so")
    func aGroupedUpgradeNamesEveryPackage() {
        let record = Self.record(name: "", verb: MutationCommand.upgradeAll.verb)

        #expect(record.subject == .everyPackage)
        #expect(record.subject.label == "All packages")
    }

    /// The durable spelling, pinned. Renaming the case without a migration would
    /// silently reclassify every stored grouped upgrade as "no package".
    @Test("The grouped verb's durable spelling is upgradeAll")
    func theGroupedVerbsDurableSpellingIsPinned() {
        #expect(MutationCommand.upgradeAll.verb == "upgradeAll")
    }

    /// `brew update` acts on Homebrew itself: not one package, and — unlike the
    /// grouped upgrade — not every package either. Its subject names the scope,
    /// the same way a cleanup entry names its own.
    @Test("A Homebrew update names Homebrew, never a package or every package")
    func aHomebrewUpdateNamesHomebrew() {
        let record = Self.record(name: "", verb: MutationCommand.update.verb)

        #expect(record.subject == .operationScope("Homebrew"))
        #expect(record.subject.label == "Homebrew")
        #expect(record.subject != .everyPackage)
    }

    /// Pinned like `upgradeAll`'s: stored rows are found again by this spelling.
    @Test("The update verb's durable spelling is update")
    func theUpdateVerbsDurableSpellingIsPinned() {
        #expect(MutationCommand.update.verb == "update")
    }

    // MARK: - CRITICAL — a null package identity is not "every package"

    @Test("Each service verb records an entry that names no package, and never every package")
    func aServiceEntryNamesNoPackage() throws {
        let verbs = try Self.serviceVerbs()
        #expect(verbs.count == 4)

        for verb in verbs {
            let record = Self.record(name: "", verb: verb)

            #expect(record.subject == .noPackage, "\(verb)")
            #expect(
                record.subject != .everyPackage,
                "\(verb) is displayed as every package on the machine"
            )
            #expect(record.subject.label == "No package", "\(verb)")
            #expect(record.subject.label != "All packages", "\(verb)")
        }
    }

    /// The service name reaches the row through the argv, which is display-only,
    /// and never through the identity slot (IH1: no synthesized identity).
    @Test("The service's own name is not borrowed into the package identity")
    func theServiceNameIsNotBorrowedIntoTheIdentity() {
        let argv = ["services", "stop", "atuin"]
        let record = HistoryRecord(
            HistoryEntry(
                id: UUID(),
                date: Date(timeIntervalSince1970: 1_000),
                kindRaw: "",
                name: "",
                verb: "serviceStop",
                versionFrom: "",
                versionTo: "",
                outcomeRaw: "succeeded",
                exitStatus: 0,
                argv: argv,
                commandText: argv.joined(separator: " ")
            )
        )

        #expect(record.subject == .noPackage)
        #expect(record.subject.label.contains("atuin") == false)
        // The argv still carries it, verbatim, where it is not an identity.
        #expect(record.commandText == "services stop atuin")
    }

    /// A verb this build has never heard of degrades to "no package", never to
    /// "every package": claiming a machine-wide operation is the expensive
    /// mistake, so the grouped label is opt-in by verb rather than a default.
    @Test("An unknown null-identity verb degrades to no package, not to every package")
    func anUnknownNullIdentityVerbDegradesToNoPackage() {
        for verb in ["", "somethingNew", "upgradeall", "UpgradeAll", "upgrade"] {
            let record = Self.record(name: "", verb: verb)

            #expect(record.subject == .noPackage, "\(verb)")
            #expect(record.subject.label == "No package", "\(verb)")
        }
    }

    // MARK: - The three facts stay three

    @Test("The three subjects are mutually exclusive and each is reachable")
    func theThreeSubjectsAreDistinct() {
        let subjects = [
            Self.record(name: "wget", kind: .formula, verb: "install").subject,
            Self.record(name: "", verb: MutationCommand.upgradeAll.verb).subject,
            Self.record(name: "", verb: "serviceStop").subject
        ]

        #expect(Set(subjects).count == 3)
        #expect(Set(subjects.map(\.label)).count == 3)
    }
}
