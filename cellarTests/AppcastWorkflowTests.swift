//
//  AppcastWorkflowTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads `.github/workflows/release.yml` off disk.
///
/// Self-contained for the same reason the rest of this slice's suites are: the
/// publication half must roll back by deleting its own files and reverting one
/// workflow hunk.
nonisolated enum AppcastWorkflowSources {
    static let workflowPath = ".github/workflows/release.yml"

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func workflow() throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(workflowPath), encoding: .utf8)
    }

    /// The workflow cut into steps at its `- name:` boundaries.
    ///
    /// The properties worth asserting about a workflow are per-step — "the
    /// appcast is built after the release exists", "every publishing step
    /// carries the prerelease guard". Asserting that two substrings both appear
    /// somewhere in the file would pass for a workflow where they sit in
    /// different steps, which is exactly the failure being guarded against.
    static func steps(in workflow: String) -> [String] {
        var steps: [String] = []
        var current: [String]?

        for line in workflow.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- name:") {
                if let started = current { steps.append(started.joined(separator: "\n")) }
                current = [String(line)]
            } else {
                current?.append(String(line))
            }
        }
        if let last = current { steps.append(last.joined(separator: "\n")) }
        return steps
    }

    /// The `release` job's header: everything it declares before its steps.
    ///
    /// Scoped deliberately. `permissions:` also exists at workflow level, and a
    /// job-level block **replaces** the workflow-level one rather than extending
    /// it — so "the file contains `contents: write`" would be satisfied by the
    /// workflow-level line while the job silently ran without it.
    static func releaseJobHeader(in workflow: String) throws -> String {
        let start = try #require(workflow.range(of: "\n  release:\n"))
        let rest = workflow[start.upperBound...]
        let end = try #require(rest.range(of: "\n    steps:"))
        return String(rest[rest.startIndex..<end.lowerBound])
    }
}

/// What the release workflow must say to publish the update feed.
@Suite("Appcast workflow")
struct AppcastWorkflowTests {
    static let prereleaseGuard = "if: ${{ !contains(github.ref_name, '-') }}"

    /// The four steps this change adds, identified by what each one runs.
    static let publicationMarkers = [
        "appcast.sh",
        "actions/configure-pages",
        "actions/upload-pages-artifact",
        "actions/deploy-pages"
    ]

    // MARK: - T16 — ordering and the prerelease guard

    /// The feed is built **after** the release exists.
    ///
    /// The item's enclosure points at the published asset's download URL, so an
    /// appcast built before `gh release create` would advertise a URL that
    /// 404s — and the feed, once served, is what every installed copy trusts.
    @Test("The appcast step runs after the release is published")
    func theAppcastStepRunsAfterTheReleaseIsPublished() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())

        let publish = try #require(steps.firstIndex { $0.contains("gh release create") })
        let appcast = try #require(steps.firstIndex { $0.contains("appcast.sh") })

        #expect(publish < appcast)
        // The split is only meaningful if it found the whole job.
        #expect(steps.count > 10)
    }

    /// Every publishing step is skipped on a prerelease tag.
    ///
    /// All four, not just the first. The deploy step is the dangerous one: a
    /// prerelease that reached it with an empty artifact would replace the live
    /// site — Pages deploys are a full-site replacement — and blank the feed for
    /// every installed copy.
    @Test("All four publication steps carry the prerelease guard")
    func allFourPublicationStepsCarryThePrereleaseGuard() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())

        var guarded = 0
        for marker in Self.publicationMarkers {
            let step = try #require(steps.first { $0.contains(marker) }, "no step runs \(marker)")
            #expect(step.contains(Self.prereleaseGuard), "\(marker) is not guarded")
            guarded += 1
        }
        #expect(guarded == 4)
    }

    // MARK: - T17 — the job header

    /// The three permissions and the deployment environment, on the job.
    ///
    /// `contents: write` is restated deliberately. A job-level `permissions:`
    /// block replaces the workflow-level one rather than extending it, so
    /// omitting it here would silently strip `gh release create` of its token —
    /// a failure that appears only on a real tag, after Apple has already been
    /// asked for a notarization round trip.
    @Test("The release job declares the Pages permissions and environment")
    func theReleaseJobDeclaresThePagesPermissionsAndEnvironment() throws {
        let header = try AppcastWorkflowSources.releaseJobHeader(in: try AppcastWorkflowSources.workflow())

        #expect(header.contains("permissions:"))
        #expect(header.contains("contents: write"))
        #expect(header.contains("pages: write"))
        #expect(header.contains("id-token: write"))
        #expect(header.contains("environment: github-pages"))
    }

    /// The secret is bound as an environment variable on the appcast step, and
    /// nowhere else.
    ///
    /// A `run:` line that interpolated the secret would put it in the command
    /// the runner logs. An `env:` binding is masked, and the script reads it
    /// from the environment onto the signing tool's standard input.
    @Test("The signing key is bound only as an environment variable")
    func theSigningKeyIsBoundOnlyAsAnEnvironmentVariable() throws {
        let workflow = try AppcastWorkflowSources.workflow()
        let naming = workflow.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("SPARKLE_PRIVATE_KEY") }

        #expect(naming.count == 1)
        let binding = try #require(naming.first)
        #expect(binding.trimmingCharacters(in: .whitespaces) == "SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}")

        let step = try #require(
            AppcastWorkflowSources.steps(in: workflow).first { $0.contains("appcast.sh") }
        )
        #expect(step.contains("SPARKLE_PRIVATE_KEY"))
    }
}
