//
//  AppcastDocument.swift
//  Updates
//

import Foundation

/// Why an appcast document is not one Cellar will act on.
///
/// Enumerated rather than stringly, and each item-scoped case carries the item's
/// index in document order: a feed grows, and "the signature is missing" is not
/// actionable on a document with eleven items.
public enum AppcastValidationFailure: Error, Sendable, Hashable {
    /// The document did not parse as XML at all.
    case malformedDocument
    /// There is no `<channel>`, so there is nothing to validate.
    case missingChannel
    case missingSignature(item: Int)
    /// The enclosure length was absent, empty, or not a number.
    case nonNumericLength(item: Int)
    case missingVersion(item: Int)
    /// The short version string was absent, empty, or unreadable as a version.
    case missingShortVersionString(item: Int)
    /// The enclosure URL was absent or did not use `https`.
    case insecureEnclosure(item: Int)
    case unexpectedHost(item: Int, expected: String)
    case wrongMinimumSystemVersion(item: Int, found: String?)
    /// A prerelease must never appear in the feed at all.
    case hyphenatedVersion(item: Int)
    /// Items were not ordered newest first, so a merge lost or reordered history.
    case itemsOutOfOrder
}

/// A validated appcast document.
///
/// A **validator over XML text**, not a client and not a builder. The CI step
/// that emits the feed cannot link this package, so the emitter stays a shell
/// heredoc; making this a validator is what puts the XML's contract under
/// `swift test` anyway. It parses with Foundation's own `XMLParser` — no updater
/// framework, no third-party XML — so it runs offline with no network and
/// without Sparkle.
public struct AppcastDocument: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public let version: String
        public let shortVersionString: String
        public let enclosureURL: URL
        public let edSignature: String
        public let length: Int
        public let minimumSystemVersion: String
    }

    /// The required host and minimum system version, fixed rather than
    /// configurable: an enclosure Cellar will download must come from the
    /// repository's own releases, and an item that claims to run on an older
    /// macOS than Cellar supports is a mis-emitted item, not a compatibility
    /// range to honour.
    public static let expectedHost = "github.com"
    public static let expectedMinimumSystemVersion = "26.0"

    /// Items in document order, newest first.
    public let items: [Item]

    public static func validate(_ xml: String) throws(AppcastValidationFailure) -> AppcastDocument {
        let reader = AppcastReader()
        guard let data = xml.data(using: .utf8), reader.read(data) else {
            throw .malformedDocument
        }
        guard reader.sawChannel else { throw .missingChannel }

        var items: [Item] = []
        for (index, raw) in reader.items.enumerated() {
            items.append(try validate(raw, at: index))
        }
        try requireDescending(items)
        return AppcastDocument(items: items)
    }

    private static func validate(_ raw: AppcastReader.RawItem, at index: Int) throws(AppcastValidationFailure) -> Item {
        let version = try require(raw.version, or: .missingVersion(item: index))
        let short = try require(raw.shortVersionString, or: .missingShortVersionString(item: index))
        guard !short.contains("-") else { throw .hyphenatedVersion(item: index) }
        guard (try? AppVersion(parsing: short)) != nil else {
            throw .missingShortVersionString(item: index)
        }

        let signature = try require(raw.edSignature, or: .missingSignature(item: index))
        guard let length = Int(raw.length?.trimmingCharacters(in: .whitespaces) ?? "") else {
            throw .nonNumericLength(item: index)
        }

        let minimum = raw.minimumSystemVersion?.trimmingCharacters(in: .whitespaces)
        guard minimum == expectedMinimumSystemVersion else {
            throw .wrongMinimumSystemVersion(item: index, found: minimum)
        }

        let url = try enclosure(raw.enclosureURL, at: index)
        return Item(
            version: version,
            shortVersionString: short,
            enclosureURL: url,
            edSignature: signature,
            length: length,
            minimumSystemVersion: expectedMinimumSystemVersion
        )
    }

    /// The enclosure has to be `https` **and** on the expected host.
    ///
    /// Both, separately: the signature check makes the transport not the thing
    /// being trusted, but an `http` enclosure is still a downgrade a network
    /// attacker chooses, and a foreign host is a feed that was rewritten rather
    /// than a release that was published.
    private static func enclosure(_ raw: String?, at index: Int) throws(AppcastValidationFailure) -> URL {
        guard let raw, let url = URL(string: raw), url.scheme == "https" else {
            throw .insecureEnclosure(item: index)
        }
        guard url.host() == expectedHost else {
            throw .unexpectedHost(item: index, expected: expectedHost)
        }
        return url
    }

    /// Newest first, strictly.
    ///
    /// The publication step prepends one item to the feed it fetched, so an
    /// out-of-order document means the merge went wrong — which is the one way
    /// history gets lost without anyone deleting anything.
    private static func requireDescending(_ items: [Item]) throws(AppcastValidationFailure) {
        let versions = items.compactMap { try? AppVersion(parsing: $0.shortVersionString, buildNumber: $0.version) }
        guard versions.count == items.count else { throw .itemsOutOfOrder }
        for (earlier, later) in zip(versions, versions.dropFirst()) where earlier <= later {
            throw .itemsOutOfOrder
        }
    }

    private static func require(
        _ value: String?,
        or failure: AppcastValidationFailure
    ) throws(AppcastValidationFailure) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Collects the raw text of every field the validator needs.
///
/// Namespace processing stays **off**, so element and attribute names arrive
/// exactly as the emitter wrote them (`sparkle:version`, `sparkle:edSignature`).
/// That is deliberate: the shell heredoc that produces the feed writes qualified
/// names, and matching on the qualified name is what keeps the two in step.
private final class AppcastReader: NSObject, XMLParserDelegate {
    struct RawItem {
        var version: String?
        var shortVersionString: String?
        var minimumSystemVersion: String?
        var enclosureURL: String?
        var edSignature: String?
        var length: String?
    }

    private(set) var items: [RawItem] = []
    private(set) var sawChannel = false
    private var current: RawItem?
    private var element: String?
    private var text = ""

    func read(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        element = elementName
        text = ""

        switch elementName {
        case "channel":
            sawChannel = true
        case "item":
            current = RawItem()
        case "enclosure":
            current?.enclosureURL = attributes["url"]
            current?.edSignature = attributes["sparkle:edSignature"]
            current?.length = attributes["length"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "sparkle:version":
            current?.version = text
        case "sparkle:shortVersionString":
            current?.shortVersionString = text
        case "sparkle:minimumSystemVersion":
            current?.minimumSystemVersion = text
        case "item":
            if let current { items.append(current) }
            current = nil
        default:
            break
        }
        element = nil
        text = ""
    }
}
