import Foundation
import Testing

@testable import Catalog

@Suite("Catalog error taxonomy")
struct CatalogErrorsTests {
    @Test("Transport errors, 429 and 5xx are retryable")
    func retryableFailures() {
        #expect(CatalogSyncError.offline.isRetryable)
        #expect(CatalogSyncError.httpStatus(429).isRetryable)
        #expect(CatalogSyncError.httpStatus(500).isRetryable)
        #expect(CatalogSyncError.httpStatus(503).isRetryable)
    }

    @Test("Other 4xx, malformed payloads, persistence and cancellation are not retryable")
    func nonRetryableFailures() {
        #expect(CatalogSyncError.httpStatus(404).isRetryable == false)
        #expect(CatalogSyncError.httpStatus(400).isRetryable == false)
        #expect(CatalogSyncError.malformedPayload.isRetryable == false)
        #expect(CatalogSyncError.persistence.isRetryable == false)
        #expect(CatalogSyncError.cancelled.isRetryable == false)
    }

    @Test("Status distinguishes download progress values")
    func statusEquality() {
        #expect(CatalogSyncStatus.downloading(fractionCompleted: 0.5)
            != CatalogSyncStatus.downloading(fractionCompleted: nil))
        #expect(CatalogSyncStatus.downloading(fractionCompleted: 0.5)
            == CatalogSyncStatus.downloading(fractionCompleted: 0.5))
        #expect(CatalogSyncStatus.idle != CatalogSyncStatus.decoding)
    }

    @Test("A failed status carries the exact failure")
    func statusCarriesFailure() throws {
        let status = CatalogSyncStatus.failed(.httpStatus(404))
        guard case .failed(let error) = status else {
            Issue.record("expected a failed status")
            return
        }
        #expect(error == .httpStatus(404))
        #expect(error != .offline)
    }

    @Test("A succeeded status carries its completion instant")
    func statusCarriesSuccessInstant() {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let status = CatalogSyncStatus.succeeded(at: instant)
        #expect(status == .succeeded(at: instant))
        #expect(status != .succeeded(at: instant.addingTimeInterval(1)))
    }
}
