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

    /// Whether `text` shells out to `command` as a command word.
    ///
    /// Substring matching would find `gh` inside `github.repository`, so the
    /// token boundary is what makes "this step shells out to `gh`" a claim
    /// worth asserting at all.
    static func invokes(_ command: String, in text: String) -> Bool {
        let pattern = "(?:^|[\\s;|&(])\(NSRegularExpression.escapedPattern(for: command))(?=\\s|$)"
        return text.split(separator: "\n", omittingEmptySubsequences: false).contains {
            String($0).range(of: pattern, options: [.regularExpression]) != nil
        }
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

    /// The five publication steps, identified by what each one runs.
    ///
    /// The guard is one of them: it is the step that decides whether this commit
    /// may publish a feed at all, so a prerelease must skip it for the same
    /// reason a prerelease skips the deploy.
    static let publicationMarkers = [
        "Refuse a second feed deployment from this commit",
        "appcast.sh",
        "actions/configure-pages",
        "actions/upload-pages-artifact",
        "actions/deploy-pages"
    ]

    static let deployStepMarker = "- name: Deploy to Pages"
    static let guardStepMarker = "- name: Refuse a second feed deployment from this commit"

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
    /// All five, not just the first. The deploy step is the dangerous one: a
    /// prerelease that reached it with an empty artifact would replace the live
    /// site — Pages deploys are a full-site replacement — and blank the feed for
    /// every installed copy.
    @Test("All five publication steps carry the prerelease guard")
    func allFivePublicationStepsCarryThePrereleaseGuard() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())

        var guarded = 0
        for marker in Self.publicationMarkers {
            let step = try #require(steps.first { $0.contains(marker) }, "no step runs \(marker)")
            #expect(step.contains(Self.prereleaseGuard), "\(marker) is not guarded")
            guarded += 1
        }
        #expect(guarded == 5)
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

    // MARK: - One stable release per commit

    /// `actions/deploy-pages` is what deploys the feed.
    ///
    /// The action sends the commit SHA as the build version, and the Pages
    /// deployments API accepts **only** a build version that is a commit in the
    /// repository: a `<sha>-<run>` string and a synthetic forty-hex string both
    /// answer 404. The action already sends the one value the API takes, so
    /// there is nothing left for a hand-rolled request to improve on.
    @Test("The appcast is deployed by actions/deploy-pages")
    func theAppcastIsDeployedByTheDeployPagesAction() throws {
        let workflow = try AppcastWorkflowSources.workflow()

        #expect(workflow.contains("actions/deploy-pages"))
        #expect(workflow.contains("actions/configure-pages"))
        #expect(workflow.contains("actions/upload-pages-artifact"))

        let deploy = try #require(
            AppcastWorkflowSources.steps(in: workflow).first { $0.contains(Self.deployStepMarker) }
        )
        #expect(deploy.contains("actions/deploy-pages"))
    }

    /// Nothing in the workflow names the build version.
    ///
    /// The only value the API accepts is the commit SHA, which is what the
    /// action sends unprompted. Every override this repository has tried —
    /// `${{ github.sha }}-${{ github.run_number }}` among them — was rejected
    /// with a 404, and the rejection landed *after* the release was published.
    @Test("The workflow never overrides the Pages build version")
    func theWorkflowNeverOverridesThePagesBuildVersion() throws {
        let workflow = try AppcastWorkflowSources.workflow()

        #expect(!workflow.contains("pages_build_version"))
        #expect(!workflow.contains("BUILD_VERSION"))
    }

    /// The commit may not have deployed the feed already.
    ///
    /// Pages keys a deployment by its build version, and the build version is
    /// the commit SHA. Asking it to deploy a commit it has already deployed is
    /// accepted, reports `succeed`, and leaves the previously published site in
    /// place — so a second stable tag on one commit would publish a release the
    /// feed never learns about. Two stable tags did point at one commit here:
    /// `v0.0.2` and `v0.0.3`.
    @Test("A guard refuses a second feed deployment from one commit")
    func aGuardRefusesASecondFeedDeploymentFromOneCommit() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())
        let step = try #require(steps.first { $0.contains(Self.guardStepMarker) })

        #expect(step.contains(Self.prereleaseGuard))
        #expect(step.contains("pages/deployments/${GITHUB_SHA}"))
        // The API answers 200 for every SHA it is asked about; what separates a
        // deployed commit from an undeployed one is the `status` in the body —
        // `succeed` against an empty string. A guard that read the HTTP code
        // would refuse every release.
        #expect(step.contains("succeed"))
        #expect(step.contains("exit 1"))
    }

    /// The guard runs before anything Apple is asked for.
    ///
    /// A commit that cannot publish a feed cannot publish a release either, and
    /// finding that out after notarization — which is what happened on
    /// `v0.0.4` — means the release is already on the tag with no feed behind
    /// it. So the guard sits with the other refusals at the top of the job.
    @Test("The guard runs before notarization and before the release is published")
    func theGuardRunsBeforeNotarizationAndBeforeTheReleaseIsPublished() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())

        let refuseGuard = try #require(steps.firstIndex { $0.contains(Self.guardStepMarker) })
        let privateRepo = try #require(steps.firstIndex { $0.contains("Refuse to publish from a private repository") })
        let notarize = try #require(steps.firstIndex { $0.contains("release.sh notarize") })
        let publish = try #require(steps.firstIndex { $0.contains("gh release create") })

        #expect(privateRepo < refuseGuard)
        #expect(refuseGuard < notarize)
        #expect(refuseGuard < publish)
    }

    /// The guard reaches the API with `curl`, and with nothing that could touch
    /// a release.
    ///
    /// The workflow's blast radius is pinned elsewhere at exactly one `gh`
    /// invocation — `gh release create` — and no `git` invocation. Reading the
    /// deployments API through `gh` here would quietly widen it.
    @Test("The guard reaches the API with curl and not gh")
    func theGuardReachesTheAPIWithCurlAndNotGh() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())
        let step = try #require(steps.first { $0.contains(Self.guardStepMarker) })

        #expect(AppcastWorkflowSources.invokes("curl", in: step))
        #expect(!AppcastWorkflowSources.invokes("gh", in: step))
        #expect(!AppcastWorkflowSources.invokes("git", in: step))
    }

    /// The deploy step keeps its place in the job.
    ///
    /// It must come after the upload, whose artifact it deploys, and before the
    /// `if: always()` cleanup that destroys the keychain and the API key — so a
    /// deployment that takes its full ten minutes never races the teardown.
    @Test("The deploy step runs after the upload and before the keychain cleanup")
    func theDeployStepRunsAfterTheUploadAndBeforeTheKeychainCleanup() throws {
        let steps = AppcastWorkflowSources.steps(in: try AppcastWorkflowSources.workflow())

        let upload = try #require(steps.firstIndex { $0.contains("actions/upload-pages-artifact") })
        let deploy = try #require(steps.firstIndex { $0.contains(Self.deployStepMarker) })
        let cleanup = try #require(steps.firstIndex { $0.contains("security delete-keychain") })

        #expect(upload < deploy)
        #expect(deploy < cleanup)
    }
}
