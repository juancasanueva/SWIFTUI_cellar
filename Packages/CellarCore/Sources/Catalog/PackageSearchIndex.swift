import Foundation

/// How strongly a record matched, strongest first.
public enum MatchRank: Int, Comparable, Sendable, CaseIterable {
    case exactToken = 0
    case namePrefix
    case nameSubstring
    case descriptionSubstring

    public static func < (lhs: MatchRank, rhs: MatchRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Every predicate the persisted catalog can actually answer.
///
/// There is deliberately no `installed`, `notInstalled` or `outdated`: those are
/// facts about the local machine, not about the published catalog, and offering
/// them here would be a promise this data cannot keep (package-search PS4).
public struct SearchFilters: Sendable, Equatable {
    public var kinds: Set<PackageKind>
    public var excludeDeprecated: Bool
    public var excludeDisabled: Bool

    public init(
        kinds: Set<PackageKind> = [.formula, .cask],
        excludeDeprecated: Bool = false,
        excludeDisabled: Bool = false
    ) {
        self.kinds = kinds
        self.excludeDeprecated = excludeDeprecated
        self.excludeDisabled = excludeDisabled
    }
}

/// One result: which package, and how well it matched.
public struct SearchHit: Sendable, Hashable, Identifiable {
    public let id: PackageID
    public let rank: MatchRank

    public init(id: PackageID, rank: MatchRank) {
        self.id = id
        self.rank = rank
    }
}

/// An immutable, queryable view of one snapshot.
///
/// Struct-of-arrays rather than an array of structs: the searchable text of
/// ~16,000 records lives in two contiguous `[UInt8]` buffers with parallel range
/// arrays, so a query is a linear byte scan over ~1–2 MB with no per-record
/// allocation and no pointer chasing. It is `Sendable` by composition — every
/// stored property is a value type — so handing a freshly built index to the
/// main actor needs no `@unchecked` and no lock.
public struct PackageSearchIndex: Sendable {
    private let names: [UInt8]
    private let nameRanges: [Range<Int>]
    private let descriptions: [UInt8]
    private let descriptionRanges: [Range<Int>]
    /// `absentCount` where the package has no analytics entry.
    private let installCounts: [Int32]
    private let kinds: [UInt8]
    private let flags: [UInt8]
    private let packages: [CatalogPackage]
    private let positions: [PackageID: Int]

    static let absentCount = Int32.min
    private static let deprecatedFlag: UInt8 = 1 << 0
    private static let disabledFlag: UInt8 = 1 << 1

    public var recordCount: Int { packages.count }

    // MARK: - Build

    /// Normalises every record exactly once, in one pass over the snapshot
    /// (package-search PS6).
    public init(snapshot: CatalogSnapshot) {
        let records = snapshot.packages
        var names: [UInt8] = []
        var nameRanges: [Range<Int>] = []
        var descriptions: [UInt8] = []
        var descriptionRanges: [Range<Int>] = []
        var installCounts: [Int32] = []
        var kinds: [UInt8] = []
        var flags: [UInt8] = []
        var positions: [PackageID: Int] = [:]

        names.reserveCapacity(records.count * 16)
        descriptions.reserveCapacity(records.count * 48)
        nameRanges.reserveCapacity(records.count)
        descriptionRanges.reserveCapacity(records.count)
        installCounts.reserveCapacity(records.count)
        kinds.reserveCapacity(records.count)
        flags.reserveCapacity(records.count)
        positions.reserveCapacity(records.count)

        for (offset, package) in records.enumerated() {
            let name = PackageText.normalize(package.name)
            nameRanges.append(names.count..<(names.count + name.count))
            names.append(contentsOf: name)

            let description = PackageText.normalize(package.desc ?? "")
            descriptionRanges.append(descriptions.count..<(descriptions.count + description.count))
            descriptions.append(contentsOf: description)

            installCounts.append(
                package.installCount365d.map { Int32(clamping: $0) } ?? Self.absentCount
            )
            kinds.append(package.kind == .formula ? 0 : 1)

            var packageFlags: UInt8 = 0
            if package.deprecated { packageFlags |= Self.deprecatedFlag }
            if package.disabled { packageFlags |= Self.disabledFlag }
            flags.append(packageFlags)

            positions[package.id] = offset
        }

        self.names = names
        self.nameRanges = nameRanges
        self.descriptions = descriptions
        self.descriptionRanges = descriptionRanges
        self.installCounts = installCounts
        self.kinds = kinds
        self.flags = flags
        packages = records
        self.positions = positions
    }

    /// Builds an index off the caller's executor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `CatalogDecoder.decode` (M1 D2): normalising ~16,000 records is tens of
    /// milliseconds of CPU, and the caller is the main actor. The built value
    /// crosses back with no lock — the index is `Sendable` by composition
    /// (design D1).
    @concurrent
    public static func build(from snapshot: CatalogSnapshot) async -> PackageSearchIndex {
        PackageSearchIndex(snapshot: snapshot)
    }

    public init() {
        self.init(
            snapshot: CatalogSnapshot(
                generatedAt: Date(timeIntervalSince1970: 0),
                skippedRecordCount: 0,
                packages: []
            )
        )
    }

    // MARK: - Lookup

    /// The full record for an id, or `nil`.
    ///
    /// A miss is an ordinary answer, never an error: the catalog covers two taps
    /// and everything else is simply not in it (package-detail PD1, PD6).
    public func package(_ id: PackageID) -> CatalogPackage? {
        positions[id].map { packages[$0] }
    }

    public func package(at offset: Int) -> CatalogPackage { packages[offset] }

    func normalizedName(at offset: Int) -> [UInt8] {
        Array(names[nameRanges[offset]])
    }

    func normalizedDescription(at offset: Int) -> [UInt8] {
        Array(descriptions[descriptionRanges[offset]])
    }

    // MARK: - Search

    /// Ranked matches, best first, capped at `limit`.
    public func search(
        _ query: String,
        filters: SearchFilters = SearchFilters(),
        limit: Int = 200
    ) -> [SearchHit] {
        let needle = PackageText.normalize(query)
        guard !needle.isEmpty else { return defaultOrder(filters: filters, limit: limit) }

        var buckets: [[Int]] = [[], [], [], []]
        names.withUnsafeBufferPointer { nameBytes in
            descriptions.withUnsafeBufferPointer { descriptionBytes in
                needle.withUnsafeBufferPointer { needleBytes in
                    for offset in 0..<packages.count {
                        guard admits(offset, filters) else { continue }
                        guard
                            let rank = rank(
                                offset,
                                needle: needleBytes,
                                names: nameBytes,
                                descriptions: descriptionBytes
                            )
                        else { continue }
                        buckets[rank.rawValue].append(offset)
                    }
                }
            }
        }

        var hits: [SearchHit] = []
        hits.reserveCapacity(min(limit, buckets.reduce(0) { $0 + $1.count }))
        for rank in MatchRank.allCases {
            guard hits.count < limit else { break }
            // Sorted lazily, best bucket first: a one-character query fills the
            // limit long before the huge description bucket is ever ordered.
            for offset in buckets[rank.rawValue].sorted(by: precedes) {
                hits.append(SearchHit(id: packages[offset].id, rank: rank))
                if hits.count >= limit { break }
            }
        }
        return hits
    }

    /// The whole filtered catalog in the documented default order.
    private func defaultOrder(filters: SearchFilters, limit: Int) -> [SearchHit] {
        var offsets: [Int] = []
        offsets.reserveCapacity(packages.count)
        for offset in 0..<packages.count where admits(offset, filters) {
            offsets.append(offset)
        }
        return offsets.sorted(by: precedes).prefix(limit).map {
            SearchHit(id: packages[$0].id, rank: .exactToken)
        }
    }

    // MARK: - Ranking

    /// `(rank asc, installCount desc, name asc, formula before cask)`.
    ///
    /// Total and reproducible by construction — no two distinct records can
    /// compare equal, because `(name, kind)` is unique.
    private func precedes(_ lhs: Int, _ rhs: Int) -> Bool {
        let leftCount = installCounts[lhs]
        let rightCount = installCounts[rhs]
        if leftCount != rightCount {
            // Absent is not "low": it is "unmeasured", and unmeasured sorts
            // after every measurement, including zero.
            if leftCount == Self.absentCount { return false }
            if rightCount == Self.absentCount { return true }
            return leftCount > rightCount
        }

        let leftName = names[nameRanges[lhs]]
        let rightName = names[nameRanges[rhs]]
        if !leftName.elementsEqual(rightName) {
            return leftName.lexicographicallyPrecedes(rightName)
        }

        return kinds[lhs] < kinds[rhs]
    }

    private func admits(_ offset: Int, _ filters: SearchFilters) -> Bool {
        let kind: PackageKind = kinds[offset] == 0 ? .formula : .cask
        guard filters.kinds.contains(kind) else { return false }
        let packageFlags = flags[offset]
        if filters.excludeDeprecated, packageFlags & Self.deprecatedFlag != 0 { return false }
        if filters.excludeDisabled, packageFlags & Self.disabledFlag != 0 { return false }
        return true
    }

    /// The strongest class this record matches, or `nil` for no match.
    ///
    /// Name checks run first and return immediately, so a name hit never pays
    /// for the description scan.
    private func rank(
        _ offset: Int,
        needle: UnsafeBufferPointer<UInt8>,
        names nameBytes: UnsafeBufferPointer<UInt8>,
        descriptions descriptionBytes: UnsafeBufferPointer<UInt8>
    ) -> MatchRank? {
        let nameRange = nameRanges[offset]
        let name = UnsafeBufferPointer(rebasing: nameBytes[nameRange])

        if Self.equals(name, needle) || Self.hasToken(name, needle) { return .exactToken }
        if Self.hasPrefix(name, needle) || Self.hasTokenPrefix(name, needle) { return .namePrefix }
        if Self.contains(name, needle) { return .nameSubstring }

        let descriptionRange = descriptionRanges[offset]
        guard !descriptionRange.isEmpty else { return nil }
        let description = UnsafeBufferPointer(rebasing: descriptionBytes[descriptionRange])
        return Self.contains(description, needle) ? .descriptionSubstring : nil
    }

    // MARK: - Byte scans

    private static func equals(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ needle: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        haystack.count == needle.count && matches(haystack, needle, at: 0)
    }

    private static func hasPrefix(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ needle: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        haystack.count >= needle.count && matches(haystack, needle, at: 0)
    }

    /// Whether one space-separated token of `haystack` equals `needle`.
    ///
    /// `visual studio code` must answer to `code`: the token is what a user
    /// types, and the hyphens Homebrew uses are just separators.
    private static func hasToken(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ needle: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        forEachTokenStart(haystack) { start in
            let end = start + needle.count
            guard end <= haystack.count, end == haystack.count || haystack[end] == 0x20 else {
                return false
            }
            return matches(haystack, needle, at: start)
        }
    }

    private static func hasTokenPrefix(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ needle: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        forEachTokenStart(haystack) { start in
            start + needle.count <= haystack.count && matches(haystack, needle, at: start)
        }
    }

    private static func forEachTokenStart(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ body: (Int) -> Bool
    ) -> Bool {
        var index = 0
        while index < haystack.count {
            if index == 0 || haystack[index - 1] == 0x20, body(index) { return true }
            index += 1
        }
        return false
    }

    private static func contains(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ needle: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        guard needle.count <= haystack.count, let first = needle.first else { return false }
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
            // Cheap first-byte gate before the full comparison.
            if haystack[start] == first, matches(haystack, needle, at: start) { return true }
            start += 1
        }
        return false
    }

    private static func matches(
        _ haystack: UnsafeBufferPointer<UInt8>,
        _ needle: UnsafeBufferPointer<UInt8>,
        at start: Int
    ) -> Bool {
        var offset = 0
        while offset < needle.count {
            if haystack[start + offset] != needle[offset] { return false }
            offset += 1
        }
        return true
    }
}
