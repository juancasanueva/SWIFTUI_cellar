import Foundation

/// A payload that arrived on disk, never in memory.
public struct FetchedPayload: Sendable {
    public let fileURL: URL
    public let validators: ConditionalValidators
    public let byteCount: Int

    public init(fileURL: URL, validators: ConditionalValidators, byteCount: Int) {
        self.fileURL = fileURL
        self.validators = validators
        self.byteCount = byteCount
    }
}

/// What a conditional request came back with.
public enum CatalogFetchOutcome: Sendable {
    /// The origin confirmed the stored validators still describe the resource.
    case notModified
    case downloaded(FetchedPayload)
}

/// The one way catalog bytes enter the process.
///
/// Deliberately narrow and deliberately file-based: a 31 MB body must stream to
/// disk rather than materialise as `Data` (catalog-sync CS1).
public protocol CatalogSource: Sendable {
    func fetch(
        _ resource: CatalogResource,
        validators: ConditionalValidators?,
        into directory: URL
    ) async throws -> CatalogFetchOutcome
}

/// The real thing: `formulae.brew.sh` over HTTPS.
public struct HTTPCatalogSource: CatalogSource {
    public static let defaultBaseURL = URL(string: "https://formulae.brew.sh/api/")!

    private let baseURL: URL
    private let session: URLSession
    private let byteLimit: Int

    public init(
        baseURL: URL = HTTPCatalogSource.defaultBaseURL,
        byteLimit: Int = 128 * 1_048_576
    ) {
        self.baseURL = baseURL
        self.byteLimit = byteLimit

        let configuration = URLSessionConfiguration.ephemeral
        // Belt: no URL cache at all. Without this a cached 200 can be replayed
        // in place of the origin's 304, and the "unchanged" signal — the whole
        // point of revalidating — silently disappears (design D7).
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    public func path(for resource: CatalogResource) -> String {
        switch resource {
        case .formulae: "formula.json"
        case .casks: "cask.json"
        case .analyticsFormula: "analytics/install-on-request/365d.json"
        case .analyticsCask: "analytics/cask-install/365d.json"
        }
    }

    public func fetch(
        _ resource: CatalogResource,
        validators: ConditionalValidators?,
        into directory: URL
    ) async throws -> CatalogFetchOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent(path(for: resource)))
        // Braces: even with no cache configured, an intermediate could serve a
        // stored response for a request that did not forbid it.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = validators?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await session.download(for: request)
        } catch is CancellationError {
            throw CatalogSyncError.cancelled
        } catch {
            throw CatalogSyncError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: downloaded)
            throw CatalogSyncError.malformedPayload
        }

        // Checked before the temp file is touched: a 304 from `download(for:)`
        // yields an empty file, which would decode as an empty catalog.
        if http.statusCode == 304 {
            try? FileManager.default.removeItem(at: downloaded)
            return .notModified
        }

        guard (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: downloaded)
            throw CatalogSyncError.httpStatus(http.statusCode)
        }

        let byteCount = (try? FileManager.default
            .attributesOfItem(atPath: downloaded.path)[.size] as? Int) ?? 0
        guard byteCount <= byteLimit else {
            try? FileManager.default.removeItem(at: downloaded)
            throw CatalogSyncError.malformedPayload
        }

        let destination = directory.appendingPathComponent("\(resource.rawValue).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: downloaded, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: downloaded)
            throw CatalogSyncError.persistence
        }

        return .downloaded(
            FetchedPayload(
                fileURL: destination,
                validators: ConditionalValidators(
                    etag: http.value(forHTTPHeaderField: "ETag"),
                    // Kept as the raw header string on purpose (design D7).
                    lastModified: http.value(forHTTPHeaderField: "Last-Modified")
                ),
                byteCount: byteCount
            )
        )
    }
}
