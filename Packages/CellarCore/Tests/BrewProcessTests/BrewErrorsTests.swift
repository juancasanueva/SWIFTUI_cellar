import Foundation
import Testing

@testable import BrewProcess

@Suite("Brew error taxonomy")
struct BrewErrorsTests {
    private let brewURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")

    @Test("An unavailable executable error carries the URL it failed on")
    func executableUnavailableCarriesURL() {
        let error = BrewProcessError.executableUnavailable(brewURL)

        #expect(error == .executableUnavailable(brewURL))
        #expect(error != .executableUnavailable(URL(fileURLWithPath: "/usr/local/bin/brew")))
    }

    @Test("A launch failure carries both the URL and the POSIX code")
    func launchFailedCarriesCode() {
        let error = BrewProcessError.launchFailed(brewURL, code: 13)

        #expect(error == .launchFailed(brewURL, code: 13))
        #expect(error != .launchFailed(brewURL, code: 2))
    }

    @Test("An unresponsive cancellation carries the elapsed grace budget")
    func cancelledUnresponsiveCarriesDuration() {
        let error = BrewProcessError.cancelledUnresponsive(after: .seconds(5))

        #expect(error == .cancelledUnresponsive(after: .seconds(5)))
        #expect(error != .cancelledUnresponsive(after: .seconds(3)))
    }

    @Test("Validation failures are distinct typed reasons, not a shared bag")
    func validationReasonsAreDistinct() {
        let notExecutable = BrewValidationError.notExecutable(brewURL)
        let notHomebrew = BrewValidationError.notHomebrew(brewURL, output: "git version 2.4.0")

        #expect(notExecutable != notHomebrew)
        #expect(notHomebrew == .notHomebrew(brewURL, output: "git version 2.4.0"))
        #expect(notHomebrew != .notHomebrew(brewURL, output: "Homebrew 4.0.0"))
    }

    @Test("A too-old version failure carries both the found and minimum versions")
    func versionTooOldCarriesBothVersions() {
        let error = BrewValidationError.versionTooOld(
            BrewVersion(major: 3, minor: 6, patch: 21),
            minimum: BrewVersion(major: 4, minor: 0, patch: 0)
        )

        guard case .versionTooOld(let found, let minimum) = error else {
            Issue.record("expected .versionTooOld, got \(error)")
            return
        }
        #expect(found == BrewVersion(major: 3, minor: 6, patch: 21))
        #expect(minimum == BrewVersion(major: 4, minor: 0, patch: 0))
    }

    @Test("A probe failure carries the diagnostic message")
    func probeFailedCarriesMessage() {
        let error = BrewValidationError.probeFailed(brewURL, message: "spawn refused")

        #expect(error == .probeFailed(brewURL, message: "spawn refused"))
        #expect(error != .probeFailed(brewURL, message: "timed out"))
    }
}
