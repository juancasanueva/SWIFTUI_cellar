import BrewProcess
import Catalog
import CryptoKit
import DiskUsage
import Foundation
public struct CleanupRow: Sendable, Hashable {
    public let path: String
    public let bytes: Int64
    public init(path: String, bytes: Int64) { self.path = path; self.bytes = bytes }
}
public enum CleanupReportedTotal: Sendable, Hashable {
    case reportedFooter(bytes: Int64), unknown
}
public enum CleanupOrphans: Sendable, Hashable {
    case notApplicable, unknown
    case known(names: [String], reportedCount: Int, currentlyOnDiskBytes: Int64?)
    public var currentlyOnDiskBytes: Int64? {
        guard case .known(_, _, let bytes) = self else { return nil }
        return bytes
    }
}
public enum CleanupParseIssue: String, Sendable, Hashable {
    case malformedSize, unknownLine, malformedAutoremove, orphanCountMismatch
}
public enum CleanupFooterForm: String, Sendable, Hashable {
    case wouldFree, hasFreed
}
public struct CleanupParserProvenance: Sendable, Hashable {
    public let parserVersion: Int
    public let footerForm: CleanupFooterForm?
    public init(parserVersion: Int = 2, footerForm: CleanupFooterForm?) {
        self.parserVersion = parserVersion; self.footerForm = footerForm
    }
}
public struct CleanupEvidenceFingerprint: Sendable, Hashable {
    public let version: Int
    public let hexadecimal: String
    init(evidence: CleanupEvidence) {
        version = 2
        let digest = SHA256.hash(data: evidence.canonicalData(version: version))
        hexadecimal = digest.map { String(format: "%02x", $0) }.joined()
    }
}
public struct CleanupEvidence: Sendable, Hashable {
    public let scope: CleanupScope
    public let rows: [CleanupRow]
    /// Paths from `Would remove (empty directory): <path>` lines. Brew prints
    /// them with no size, so they never become rows: a zero-byte row would
    /// claim a size brew never reported.
    public let emptyDirectories: [String]
    public let orphans: CleanupOrphans
    public let total: CleanupReportedTotal
    public let unknownLines: [Data]
    public let issues: Set<CleanupParseIssue>
    public init(
        scope: CleanupScope,
        rows: [CleanupRow],
        emptyDirectories: [String],
        orphans: CleanupOrphans,
        total: CleanupReportedTotal,
        unknownLines: [Data],
        issues: Set<CleanupParseIssue>
    ) {
        self.scope = scope
        self.rows = rows
        self.emptyDirectories = emptyDirectories
        self.orphans = orphans
        self.total = total
        self.unknownLines = unknownLines
        self.issues = issues
    }
    public var isPartial: Bool { !issues.isEmpty }
    public var isEmpty: Bool {
        switch orphans {
        case .known(let names, _, _): names.isEmpty && unknownLines.isEmpty
        case .notApplicable:
            rows.isEmpty && emptyDirectories.isEmpty && total == .unknown && unknownLines.isEmpty
        case .unknown: false
        }
    }
    public var fingerprint: CleanupEvidenceFingerprint { CleanupEvidenceFingerprint(evidence: self) }
    /// Compares every typed authorization fact, never a hash alone.
    public func isEqualForAuthorization(to other: CleanupEvidence) -> Bool { self == other }
    fileprivate func canonicalData(version: Int) -> Data {
        var encoder = CleanupCanonicalEncoder()
        encoder.append("cellar.cleanup.evidence")
        encoder.append(version)
        switch scope {
        case .global: encoder.append("scope.global")
        case .full: encoder.append("scope.full")
        case .autoremove: encoder.append("scope.autoremove")
        case .package(let target):
            encoder.append("scope.package")
            encoder.append(target.kind.rawValue)
            encoder.append(target.name)
        }
        encoder.append(rows.count)
        for row in rows {
            encoder.append(row.path)
            encoder.append(row.bytes)
        }
        encoder.append(emptyDirectories.count)
        for path in emptyDirectories { encoder.append(path) }
        switch orphans {
        case .notApplicable: encoder.append("orphans.na")
        case .unknown: encoder.append("orphans.unknown")
        case .known(let names, let count, let allocation):
            encoder.append("orphans.known")
            encoder.append(count)
            encoder.append(names.count)
            for name in names { encoder.append(name) }
            encoder.append(allocation)
        }
        switch total {
        case .unknown: encoder.append("total.unknown")
        case .reportedFooter(let bytes):
            encoder.append("total.footer")
            encoder.append(bytes)
        }
        encoder.append(unknownLines.count)
        for line in unknownLines { encoder.append(line) }
        let orderedIssues = issues.map(\.rawValue).sorted()
        encoder.append(orderedIssues.count)
        for issue in orderedIssues { encoder.append(issue) }
        return encoder.data
    }
}
public struct CleanupPreviewRequest: Sendable, Equatable {
    public let id: UUID
    public let scope: CleanupScope
    public let specification: BrewCommand
    public init(id: UUID = UUID(), scope: CleanupScope) {
        self.id = id
        self.scope = scope
        specification = CleanupCommand(scope: scope).previewCommand
    }
}
public struct CleanupDiskUsageContext: Sendable, Hashable {
    public let snapshot: DiskUsageSnapshot
    public let expectedRoots: DiskRootsIdentity
    public init(snapshot: DiskUsageSnapshot, expectedRoots: DiskRootsIdentity) {
        self.snapshot = snapshot; self.expectedRoots = expectedRoots
    }
}
public struct CleanupPreviewResult: Sendable, Hashable {
    public let requestID: UUID
    public let rawStdout: Data
    public let rawStderr: Data
    public let evidence: CleanupEvidence
    public let provenance: CleanupParserProvenance
}
public enum CleanupParser {
    public static func parse(
        _ request: CleanupPreviewRequest,
        rawStdout: Data,
        rawStderr: Data,
        diskUsage: CleanupDiskUsageContext? = nil
    ) -> CleanupPreviewResult {
        let parsed = switch request.scope {
        case .autoremove: parseAutoremove(rawStdout, diskUsage: diskUsage)
        case .global, .package, .full: parseCleanup(rawStdout)
        }
        return CleanupPreviewResult(
            requestID: request.id,
            rawStdout: rawStdout,
            rawStderr: rawStderr,
            evidence: CleanupEvidence(
                scope: request.scope,
                rows: parsed.rows,
                emptyDirectories: parsed.emptyDirectories,
                orphans: parsed.orphans,
                total: parsed.total,
                unknownLines: parsed.unknownLines,
                issues: parsed.issues
            ),
            provenance: .init(footerForm: parsed.footerForm)
        )
    }
    private struct Parsed {
        var rows: [CleanupRow] = []
        var emptyDirectories: [String] = []
        var orphans: CleanupOrphans = .notApplicable
        var total: CleanupReportedTotal = .unknown
        var unknownLines: [Data] = []
        var issues: Set<CleanupParseIssue> = []
        var footerForm: CleanupFooterForm?
    }
    private static func parseCleanup(_ data: Data) -> Parsed {
        var parsed = Parsed()
        for rawLine in lines(in: data) {
            guard let text = text(of: rawLine), !text.isEmpty else { continue }
            if let row = cleanupRow(text) {
                parsed.rows.append(row)
            } else if let directory = emptyDirectory(text) {
                parsed.emptyDirectories.append(directory)
            } else if let footer = footer(text) {
                parsed.total = .reportedFooter(bytes: footer.bytes)
                parsed.footerForm = footer.form
            } else {
                parsed.unknownLines.append(rawLine)
                parsed.issues.insert(text.hasPrefix("Would remove: ") || text.hasPrefix("Removing: ")
                    ? .malformedSize : .unknownLine)
            }
        }
        return parsed
    }
    private static func parseAutoremove(
        _ data: Data,
        diskUsage: CleanupDiskUsageContext?
    ) -> Parsed {
        let rawLines = lines(in: data).filter { text(of: $0)?.isEmpty == false }
        guard !rawLines.isEmpty else {
            var parsed = Parsed()
            parsed.orphans = .known(names: [], reportedCount: 0, currentlyOnDiskBytes: nil)
            return parsed
        }
        guard let header = text(of: rawLines[0]), let reportedCount = autoremoveCount(header) else {
            var parsed = Parsed()
            parsed.orphans = .unknown
            parsed.unknownLines = rawLines
            parsed.issues = [.malformedAutoremove, .unknownLine]
            return parsed
        }
        var parsed = Parsed()
        var names: [String] = []
        for rawLine in rawLines.dropFirst() {
            guard let name = text(of: rawLine), MutationName.isSafe(name) else {
                parsed.unknownLines.append(rawLine)
                parsed.issues.formUnion([.malformedAutoremove, .unknownLine])
                continue
            }
            names.append(name)
        }
        if names.count != reportedCount { parsed.issues.insert(.orphanCountMismatch) }
        let allocation = names.count == reportedCount
            ? currentlyOnDiskBytes(for: names, using: diskUsage)
            : nil
        parsed.orphans = .known(
            names: names,
            reportedCount: reportedCount,
            currentlyOnDiskBytes: allocation
        )
        return parsed
    }
    private static func cleanupRow(_ text: String) -> CleanupRow? {
        let prefixes = ["Would remove: ", "Removing: "]
        guard let prefix = prefixes.first(where: text.hasPrefix) else { return nil }
        let body = String(text.dropFirst(prefix.count))
        guard body.hasSuffix(")"), let open = body.lastIndex(of: "(") else { return nil }
        var path = String(body[..<open]).trimmingCharacters(in: .whitespaces)
        if path.hasSuffix("...") { path.removeLast(3) }
        let sizeStart = body.index(after: open)
        let size = String(body[sizeStart..<body.index(before: body.endIndex)])
        guard !path.isEmpty, let bytes = byteCount(size) else { return nil }
        return CleanupRow(path: path, bytes: bytes)
    }
    /// Dry-run only: the real run removes empty directories silently
    /// (`rmdir_if_possible` in Homebrew's cleanup.rb), so there is no
    /// `Removing (empty directory):` twin to recognize.
    private static func emptyDirectory(_ text: String) -> String? {
        let prefix = "Would remove (empty directory): "
        guard text.hasPrefix(prefix) else { return nil }
        let path = String(text.dropFirst(prefix.count))
        return path.isEmpty ? nil : path
    }
    private static func footer(_ text: String) -> (bytes: Int64, form: CleanupFooterForm)? {
        let forms: [(String, CleanupFooterForm)] = [
            ("==> This operation would free approximately ", .wouldFree),
            ("==> This operation has freed approximately ", .hasFreed),
        ]
        guard let (prefix, form) = forms.first(where: { text.hasPrefix($0.0) }),
              text.hasSuffix(" of disk space.")
        else { return nil }
        let end = text.index(text.endIndex, offsetBy: -" of disk space.".count)
        guard let bytes = byteCount(String(text[text.index(text.startIndex, offsetBy: prefix.count)..<end])) else {
            return nil
        }
        return (bytes, form)
    }
    private static func autoremoveCount(_ text: String) -> Int? {
        let prefix = "==> Would autoremove "
        let suffixes = [" unneeded formula:", " unneeded formulae:"]
        guard text.hasPrefix(prefix), let suffix = suffixes.first(where: text.hasSuffix) else { return nil }
        let start = text.index(text.startIndex, offsetBy: prefix.count)
        let end = text.index(text.endIndex, offsetBy: -suffix.count)
        return Int(text[start..<end])
    }
    private static func currentlyOnDiskBytes(
        for names: [String],
        using context: CleanupDiskUsageContext?
    ) -> Int64? {
        guard let context,
              context.snapshot.roots == context.expectedRoots,
              context.snapshot.isComplete,
              Set(context.snapshot.rootStates.keys) == Set(DiskArea.allCases)
        else { return nil }
        let packages = Dictionary(uniqueKeysWithValues: context.snapshot.packages.map { ($0.id, $0) })
        var total: Int64 = 0
        for name in names {
            guard let package = packages[PackageID(kind: .formula, name: name)] else { return nil }
            let (next, overflow) = total.addingReportingOverflow(package.observation.allocatedBytes)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
    private static func byteCount(_ source: String) -> Int64? {
        let units: [(String, Int64)] = [
            ("PB", 1 << 50), ("TB", 1 << 40), ("GB", 1 << 30),
            ("MB", 1 << 20), ("KB", 1 << 10), ("B", 1),
        ]
        guard let (unit, factor) = units.first(where: { source.hasSuffix($0.0) }) else { return nil }
        let number = String(source.dropLast(unit.count))
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let whole = Int64(parts[0]), whole >= 0 else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 3, fraction.allSatisfy({ $0.isNumber }), !fraction.isEmpty || parts.count == 1 else {
            return nil
        }
        let denominator = Int64(pow(10.0, Double(fraction.count)))
        guard let fractional = Int64(fraction.isEmpty ? "0" : fraction) else { return nil }
        let (scaledWhole, overflow1) = whole.multipliedReportingOverflow(by: denominator)
        let (numerator, overflow2) = scaledWhole.addingReportingOverflow(fractional)
        let (product, overflow3) = numerator.multipliedReportingOverflow(by: factor)
        let (rounded, overflow4) = product.addingReportingOverflow(denominator / 2)
        guard !overflow1, !overflow2, !overflow3, !overflow4 else { return nil }
        return rounded / denominator
    }
    private static func lines(in data: Data) -> [Data] {
        var result: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == UInt8(ascii: "\n") {
            let end = data.index(after: index)
            result.append(Data(data[start..<end]))
            start = end
        }
        if start < data.endIndex { result.append(Data(data[start..<data.endIndex])) }
        return result
    }
    private static func text(of rawLine: Data) -> String? {
        var content = rawLine
        if content.last == UInt8(ascii: "\n") { content.removeLast() }
        if content.last == UInt8(ascii: "\r") { content.removeLast() }
        return String(data: content, encoding: .utf8)
    }
}
private struct CleanupCanonicalEncoder {
    private(set) var data = Data()
    mutating func append(_ value: String) { append(Data(value.utf8)) }
    mutating func append(_ value: Int) { append(Int64(value)) }
    mutating func append(_ value: Int64) { append(withUnsafeBytes(of: value.bigEndian) { Data($0) }) }
    mutating func append(_ value: Int64?) {
        append(value == nil ? "nil" : "some")
        if let value { append(value) }
    }
    mutating func append(_ value: Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(value)
    }
}
