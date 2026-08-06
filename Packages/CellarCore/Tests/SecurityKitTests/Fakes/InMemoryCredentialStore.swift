import Foundation
import SecurityKit

/// The credential seam, in memory.
///
/// **No test in this package touches the real Keychain.** A test that did would
/// prompt on a developer's machine, fail in CI, and leave a real credential
/// behind — so the seam exists precisely so that never has to happen, and this
/// is the conformer every test uses.
actor InMemoryCredentialStore: AdvisoryCredentialStoring {
    private var key: String?
    private(set) var readCount = 0

    init(key: String? = nil) {
        self.key = key
    }

    func apiKey() async throws -> String? {
        readCount += 1
        return key
    }

    func store(apiKey: String) async throws {
        key = apiKey
    }

    func removeAPIKey() async throws {
        key = nil
    }
}
