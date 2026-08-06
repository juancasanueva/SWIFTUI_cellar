import Foundation

/// Severity enrichment against `services.nvd.nist.gov`.
///
/// ## Why this exists as a separate source
///
/// OSV decides *affectedness* and NVD supplies *severity*, and neither is a
/// fallback for the other. Merging them would let a rate-limited severity lookup
/// look like a missing advisory, which is precisely the collapse this feature
/// exists to prevent.
///
/// ## Why volume follows findings
///
/// Every request here is keyed by CVE identifier — identifiers OSV already
/// returned — and by nothing else. **No request names an installed package**, so
/// a hundred and fifty-nine formulae producing three identifiers cost one
/// request, not a hundred and fifty-nine. That is a privacy property before it is
/// a performance one: NVD learns which vulnerabilities somebody asked about,
/// never what is installed on this machine.
public struct NVDSource: AdvisoryEnriching {
    /// The one host this type reaches, compiled in.
    public static let baseURL = "https://services.nvd.nist.gov/rest/json/"

    /// NVD's documented ceiling for `cveIds`.
    public static let batchSize = 100

    private let session: URLSession
    private let credentials: (any AdvisoryCredentialStoring)?
    private let byteLimit: Int

    public init(
        session: URLSession = AdvisorySession.make(),
        credentials: (any AdvisoryCredentialStoring)? = nil,
        byteLimit: Int = AdvisorySession.payloadByteLimit
    ) {
        self.session = session
        self.credentials = credentials
        self.byteLimit = byteLimit
    }

    // MARK: - Enrichment

    public func enrich(_ cveIDs: [String]) async throws(AdvisoryError) -> AdvisoryEnrichment {
        let identifiers = cveIDs.filter(Self.isWellFormedCVEIdentifier)
        guard identifiers.isEmpty == false else {
            return AdvisoryEnrichment(severities: [:], skippedRecordCount: 0)
        }

        // Read once, not once per batch: the key does not change mid-scan, and a
        // Keychain read per request is a prompt surface for no benefit. A key
        // that cannot be read is a *missing* key — enrichment continues
        // unauthenticated rather than failing the scan over a credential the
        // feature works without.
        let key = (try? await credentials?.apiKey()) ?? nil

        var severities: [String: SeverityTier] = [:]
        var skipped = 0

        for batch in stride(from: 0, to: identifiers.count, by: Self.batchSize) {
            let slice = Array(
                identifiers[batch..<min(batch + Self.batchSize, identifiers.count)]
            )
            let response = try await fetch(slice, key: key)

            for record in response.records {
                // `advertised: nil` on purpose. The advertised word is an *OSV*
                // field; NVD publishes its severity inside `cvssData`, which
                // `tiered(from:)` already reads. Passing something here would be
                // inventing a second opinion for a record that only has one.
                severities[record.cveID] = SeverityTier.tiered(
                    from: record.scores,
                    advertised: nil
                )
            }
            skipped += response.skippedRecordCount
        }

        return AdvisoryEnrichment(severities: severities, skippedRecordCount: skipped)
    }

    // MARK: - One batch

    private func fetch(
        _ identifiers: [String],
        key: String?
    ) async throws(AdvisoryError) -> NVDEnrichmentResponse {
        // Built by concatenation from a compiled-in constant and identifiers
        // whose alphabet has already been checked, so no part of the host, path
        // or parameter name comes from a value.
        guard let url = URL(
            string: Self.baseURL + "cves/2.0?cveIds=" + identifiers.joined(separator: ",")
        ) else {
            throw .transportFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key {
            // A credential belongs in a header. In the query string it would be
            // recorded verbatim by every proxy and server log on the path.
            request.setValue(key, forHTTPHeaderField: "apiKey")
        }

        let data = try await AdvisorySession.body(
            for: request,
            on: session,
            byteLimit: byteLimit
        )
        return try NVDWire.enrichment(from: data)
    }

    // MARK: - Identifiers

    /// `CVE-<year>-<sequence>`, and nothing else.
    ///
    /// Identifiers arrive from OSV's aliases, which are wire data. Restricting
    /// them to this shape is what makes the concatenated URL safe without a
    /// percent-encoding step — a value that cannot contain `&`, `?`, `/` or `#`
    /// cannot add a parameter, change a path or leave the host.
    static func isWellFormedCVEIdentifier(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "CVE" else { return false }
        guard parts[1].count == 4, parts[1].allSatisfy(\.isNumber) else { return false }
        return parts[2].isEmpty == false && parts[2].allSatisfy(\.isNumber)
    }
}
