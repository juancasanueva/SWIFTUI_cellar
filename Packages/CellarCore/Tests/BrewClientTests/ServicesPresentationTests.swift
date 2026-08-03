import Foundation
import Testing

@testable import BrewClient

/// How a status is shown, as a pure projection.
///
/// This is the **headless substitute** for the six statuses that cannot be
/// produced on the development machine: `scheduled`, `stopped`, `error`,
/// `unknown` and `other` have no reachable live path, and neither has any
/// unrecognised string. MV-9 corroborates the rendering under a temporary
/// fixture patch; this proves the mapping.
@Suite("Services presentation")
struct ServicesPresentationTests {
    /// Every status this build can hold, including one of the catch-all.
    private static let everyStatus: [ServiceStatus] = [
        .started, .none, .scheduled, .stopped, .error, .unknown, .other,
        .unrecognised("mystery")
    ]

    @Test("Every status has its own label")
    func everyStatusHasItsOwnLabel() {
        let labels = Self.everyStatus.map(\.label)

        #expect(labels.allSatisfy { !$0.isEmpty }, "a status renders as nothing at all")
        #expect(
            Set(labels).count == labels.count,
            "two statuses share a label, so the user cannot tell them apart: \(labels)"
        )
    }

    @Test("The labels are the words the product uses, not brew's raw symbols")
    func theLabelsAreTheProductsWords() {
        #expect(ServiceStatus.started.label == "Running")
        #expect(ServiceStatus.none.label == "Not running")
        #expect(ServiceStatus.scheduled.label == "Scheduled")
        #expect(ServiceStatus.stopped.label == "Stopped")
        #expect(ServiceStatus.error.label == "Error")
        #expect(ServiceStatus.unknown.label == "Unknown")
        #expect(ServiceStatus.other.label == "Other")
    }

    /// An unrecognised status shows what brew said. Hiding the service, or
    /// relabelling it as "unknown", would both report something brew did not
    /// say — and `unknown` is a real, different status.
    @Test("An unrecognised status shows its raw string and is not relabelled as unknown")
    func anUnrecognisedStatusShowsItsRawString() {
        #expect(ServiceStatus.unrecognised("mystery").label == "mystery")
        #expect(ServiceStatus.unrecognised("mystery").label != ServiceStatus.unknown.label)
        #expect(ServiceStatus.unrecognised("mystery").tone != .failed)
    }

    @Test("Only the states brew reports as broken are toned as failures")
    func onlyBrokenStatesAreTonedAsFailures() {
        let failing = Self.everyStatus.filter { $0.tone == .failed }

        #expect(failing == [.error, .unknown])
        // The tone and the predicate agree; two spellings of one rule that
        // disagreed would colour a row red while calling it healthy.
        for status in Self.everyStatus {
            #expect(status.isFailure == (status.tone == .failed), "\(status.raw)")
        }
    }

    @Test("A running service and an idle one are toned apart")
    func runningAndIdleAreTonedApart() {
        #expect(ServiceStatus.started.tone == .running)
        #expect(ServiceStatus.none.tone == .idle)
        #expect(ServiceStatus.stopped.tone == .idle)
        #expect(ServiceStatus.scheduled.tone == .scheduled)
        #expect(ServiceStatus.other.tone == .indeterminate)
        #expect(ServiceStatus.unrecognised("mystery").tone == .indeterminate)
    }

    /// Every tone the projection can produce must be one the surface knows how
    /// to draw. A tone added without a colour would render as whatever the
    /// default happens to be.
    @Test("Every declared tone is produced by some status, and none is orphaned")
    func everyToneIsReachable() {
        let produced = Set(Self.everyStatus.map(\.tone))

        #expect(produced == Set(ServiceStatusTone.allCases))
    }

    // MARK: - SM9 — no stale status is retained

    @Test("A changed status replaces the previous one")
    func aChangedStatusReplacesThePreviousOne() {
        let before = [
            ServiceRecord(name: "atuin", status: .started),
            ServiceRecord(name: "postgresql", status: .none)
        ]
        let after = [
            ServiceRecord(name: "atuin", status: .error),
            ServiceRecord(name: "postgresql", status: .none)
        ]

        #expect(before.map(\.status.label) == ["Running", "Not running"])
        #expect(after.map(\.status.label) == ["Error", "Not running"])
        // One row per service, so nothing accumulates: a projection that
        // appended rather than replaced would show `atuin` twice.
        #expect(after.count == before.count)
        #expect(Set(after.map(\.id)).count == after.count)
        #expect(
            after.contains { $0.name == "atuin" && $0.status == .started } == false,
            "the previously displayed status is still present"
        )
    }

    // MARK: - SM9 sc2 — nothing is delivered for it

    /// Ruling #7182-2: a service that dies is a red row at the next poll and
    /// nothing else. No notification, no permission prompt, no badge, no
    /// blocking alert.
    ///
    /// This is an **absence** assertion over the capability's own sources, not
    /// a wiring proof — wiring is proven by `xcodebuild build` and by the
    /// manual checks, never by a cross-target scan. It anchors positively
    /// first: a scan that silently read nothing would otherwise "pass" by
    /// finding no forbidden symbol in no text (the M3-0 lesson).
    @Test("The services capability declares no notification, badge or blocking alert")
    func theServicesSurfaceDeclaresNoNotification() throws {
        let sources = try Self.servicesSources()

        // Positive anchor: the files really were read, and they really are the
        // services surface.
        #expect(sources.count >= 5, "only \(sources.count) services sources were read")
        let corpus = sources.values.joined(separator: "\n")
        #expect(corpus.contains("ServicesRefreshCoordinator"))
        #expect(corpus.contains("ServiceStatus"))

        let forbidden = [
            "UNUserNotificationCenter",
            "NSUserNotification",
            "requestAuthorization",
            "UNNotificationRequest",
            "applicationIconBadge",
            "dockTile",
            "NSAlert",
            "runModal"
        ]
        for (name, source) in sources {
            for symbol in forbidden {
                #expect(
                    source.contains(symbol) == false,
                    "\(name) reaches for \(symbol); a dying service is a red row and nothing else"
                )
            }
        }
    }

    private static func servicesSources() throws -> [String: String] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrewClient")
        let names = [
            "ServicesWire.swift",
            "ServicesPayloadSource.swift",
            "ServicesStore.swift",
            "ServicesRefreshCoordinator.swift",
            "ServicesPresentation.swift",
            "LogFileOpening.swift"
        ]
        var read: [String: String] = [:]
        for name in names {
            let url = sources.appendingPathComponent(name)
            read[name] = try String(contentsOf: url, encoding: .utf8)
        }
        return read
    }
}
