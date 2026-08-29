import Foundation

/// 365-day install counts, keyed by `(kind, name)`.
///
/// Homebrew publishes the two namespaces as two separate flat endpoints whose
/// item key differs (`formula` vs `cask`), so the kind is supplied by the caller
/// that chose the endpoint rather than guessed from the payload.
public struct AnalyticsIndex: Sendable, Equatable {
    private var counts: [PackageID: Int]

    public init(counts: [PackageID: Int] = [:]) {
        self.counts = counts
    }

    public var isEmpty: Bool { counts.isEmpty }

    /// The count for a package, or `nil` when the endpoint listed no entry.
    ///
    /// Absent is not zero: a package outside the published ranking simply has no
    /// measurement, which is a different statement from "nobody installed it"
    /// (package-detail PD5).
    public func count(for id: PackageID) -> Int? {
        counts[id]
    }

    public func merging(_ other: AnalyticsIndex) -> AnalyticsIndex {
        AnalyticsIndex(counts: counts.merging(other.counts) { _, new in new })
    }

    /// One kind's counts keyed by bare name — the shape the per-period charts
    /// seam serves, where the kind is fixed by the endpoint that was fetched.
    public func countsByName(kind: PackageKind) -> [String: Int] {
        var result: [String: Int] = [:]
        result.reserveCapacity(counts.count)
        for (id, count) in counts where id.kind == kind {
            result[id.name] = count
        }
        return result
    }

    // MARK: - Decoding

    public static func decode(_ data: Data, kind: PackageKind) throws -> AnalyticsIndex {
        let payload: AnalyticsPayload
        do {
            payload = try JSONDecoder().decode(AnalyticsPayload.self, from: data)
        } catch {
            throw CatalogSyncError.malformedPayload
        }

        var counts: [PackageID: Int] = [:]
        counts.reserveCapacity(payload.items.count)
        for item in payload.items {
            guard let name = item.name(for: kind), let count = parseCount(item.count) else {
                continue
            }
            counts[PackageID(kind: kind, name: name)] = count
        }
        return AnalyticsIndex(counts: counts)
    }

    /// Parses the comma-grouped decimal strings the endpoint emits.
    ///
    /// Deliberately not `NumberFormatter`: a formatter reads its grouping rules
    /// from the *user's* locale, so `"2,808,879"` becomes `2` under any locale
    /// that groups with `.` — a silent, machine-dependent corruption. The API
    /// emits exactly one format, so parsing it is a string operation, not a
    /// localisation one (catalog-sync CS9).
    public static func parseCount(_ string: String) -> Int? {
        var digits = ""
        digits.reserveCapacity(string.count)
        for character in string {
            if character == "," { continue }
            guard character.isASCII, character.isNumber else { return nil }
            digits.append(character)
        }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

}

// MARK: - Wire

/// The ranked-endpoint envelope. Everything outside `items` is header material
/// the join does not need.
private struct AnalyticsPayload: Decodable {
    let items: [AnalyticsItem]
}

/// One ranked entry. Which of `formula` and `cask` is populated depends on the
/// endpoint, so the caller supplies the kind rather than the payload declaring it.
private struct AnalyticsItem: Decodable {
    let formula: String?
    let cask: String?
    let count: String

    func name(for kind: PackageKind) -> String? {
        switch kind {
        case .formula: formula
        case .cask: cask
        // Homebrew's analytics endpoints publish two item keys and neither is
        // npm's. An npm identity has no measurement here, and absent is not
        // zero: the caller reads `nil` and says nothing about install counts.
        case .npm: nil
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formula = try container.decodeIfPresent(String.self, forKey: .formula)
        cask = try container.decodeIfPresent(String.self, forKey: .cask)
        count = try container.decodeIfPresent(String.self, forKey: .count) ?? ""
    }

    enum CodingKeys: String, CodingKey { case formula, cask, count }
}
