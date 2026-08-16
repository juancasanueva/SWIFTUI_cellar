import Foundation

/// The one way per-period cask install counts enter the process.
///
/// A seam, so the store can be proven against a fake and a UI-test launch can
/// swap in a source that never touches the network.
public protocol CaskChartsSource: Sendable {
    /// Install counts keyed by bare cask token, for one analytics window.
    func fetchCounts(period: CaskChartsPeriod) async throws -> [String: Int]
}

/// The real thing: `formulae.brew.sh`'s per-window cask-install endpoints.
public struct HTTPCaskChartsSource: CaskChartsSource {
    public static let defaultBaseURL = URL(
        string: "https://formulae.brew.sh/api/analytics/cask-install/"
    )!

    private let baseURL: URL
    private let session: URLSession
    private let byteLimit: Int

    /// Well above the few megabytes the largest window actually weighs, and
    /// far below anything that could be mistaken for the 31 MB catalog.
    public init(
        baseURL: URL = HTTPCaskChartsSource.defaultBaseURL,
        session: URLSession? = nil,
        byteLimit: Int = 32 * 1_048_576
    ) {
        self.baseURL = baseURL
        self.byteLimit = byteLimit
        if let session {
            self.session = session
        } else {
            // The `HTTPCatalogSource` idiom: ephemeral, and no URL cache at
            // all, so yesterday's ranking can never be replayed as today's.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetchCounts(period: CaskChartsPeriod) async throws -> [String: Int] {
        var request = URLRequest(url: baseURL.appendingPathComponent("\(period.rawValue).json"))
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CatalogSyncError.cancelled
        } catch {
            throw CatalogSyncError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw CatalogSyncError.malformedPayload
        }
        guard (200...299).contains(http.statusCode) else {
            throw CatalogSyncError.httpStatus(http.statusCode)
        }
        guard data.count <= byteLimit else {
            throw CatalogSyncError.malformedPayload
        }

        // The existing analytics decoder, verbatim — including its locale-proof
        // comma-string parsing (CS9). This source adds transport, not decoding.
        return try AnalyticsIndex.decode(data, kind: .cask).countsByName(kind: .cask)
    }
}
