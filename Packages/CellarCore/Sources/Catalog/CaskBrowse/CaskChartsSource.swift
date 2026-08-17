import Foundation

/// The one way per-period cask install counts enter the process.
///
/// A seam, so the store can be proven against a fake and a UI-test launch can
/// swap in a source that never touches the network.
public protocol CaskChartsSource: Sendable {
    /// Install counts keyed by bare cask token, for one analytics window.
    func fetchCounts(period: CaskChartsPeriod) async throws -> [String: Int]
}

/// The real thing: `formulae.brew.sh`'s per-window install endpoints — the
/// cask ones by default, the formula ones when built with `.formula`, because
/// the origin publishes both kinds in the identical envelope.
public struct HTTPCaskChartsSource: CaskChartsSource {
    public static let defaultBaseURL = URL(
        string: "https://formulae.brew.sh/api/analytics/cask-install/"
    )!
    /// The formula windows' home: install-on-request, the same metric the
    /// catalog's own 365d join uses for formulae.
    public static let formulaBaseURL = URL(
        string: "https://formulae.brew.sh/api/analytics/install-on-request/"
    )!

    private let baseURL: URL
    private let kind: PackageKind
    private let session: URLSession
    private let byteLimit: Int

    /// Well above the few megabytes the largest window actually weighs, and
    /// far below anything that could be mistaken for the 31 MB catalog.
    public init(
        baseURL: URL = HTTPCaskChartsSource.defaultBaseURL,
        kind: PackageKind = .cask,
        session: URLSession? = nil,
        byteLimit: Int = 32 * 1_048_576
    ) {
        self.baseURL = baseURL
        self.kind = kind
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
        return try AnalyticsIndex.decode(data, kind: kind).countsByName(kind: kind)
    }
}
