import Foundation

/// The `brew info --installed --json=v2` envelope.
///
/// Both namespaces are optional so a payload carrying only one still decodes;
/// a document carrying *neither* is not this envelope at all and is rejected by
/// the decoder.
struct InstalledEnvelopeWire: Decodable {
    let formulae: LossyArray<FormulaInstalledWire>?
    let casks: LossyArray<CaskInstalledWire>?
}

/// One installed formula, trimmed to what the projection reads.
///
/// Every field except `name` is optional: the published records are written by
/// thousands of contributors and a missing key must cost that field, not the
/// record. Deliberately absent — `bottle`, `urls`, `ruby_source_checksum`,
/// `runtime_dependencies`, `used_options`, `service`, `conflicts_with` — are
/// never read, so they are never allocated (design D3).
struct FormulaInstalledWire: Decodable {
    let name: String
    let tap: String?
    let desc: String?
    let homepage: String?
    let versions: Versions?
    /// A formula's installed data is an **array of keg records**.
    let installed: [KegWire]?
    let linkedKeg: String?
    let pinned: Bool?
    let pinnedVersion: String?
    let outdated: Bool?

    struct Versions: Decodable {
        let stable: String?
    }

    struct KegWire: Decodable {
        let version: String
        /// Epoch seconds.
        let time: TimeInterval?
        let installedOnRequest: Bool?

        enum CodingKeys: String, CodingKey {
            case version
            case time
            case installedOnRequest = "installed_on_request"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, tap, desc, homepage, versions, installed, pinned, outdated
        case linkedKeg = "linked_keg"
        case pinnedVersion = "pinned_version"
    }
}

/// One installed cask, trimmed the same way.
///
/// The asymmetry lives here rather than in a custom `init(from:)`: a cask's
/// installed data is a **plain version string**, not a keg array, so the two
/// shapes are two types and the compiler enforces the difference.
struct CaskInstalledWire: Decodable {
    let token: String
    let tap: String?
    /// Casks publish a list of display names; the first is the canonical one.
    let name: [String]?
    let desc: String?
    let homepage: String?
    /// The version the published record currently offers.
    let version: String?
    let installed: String?
    /// Epoch seconds.
    let installedTime: TimeInterval?
    let outdated: Bool?
    /// Tri-state in practice: `true`, `null`, or absent. Never observed as
    /// `false`, which is why it is decoded as `Bool?` and folded later.
    let autoUpdates: Bool?
    let pinned: Bool?
    let pinnedVersion: String?

    enum CodingKeys: String, CodingKey {
        case token, tap, name, desc, homepage, version, installed, outdated, pinned
        case installedTime = "installed_time"
        case autoUpdates = "auto_updates"
        case pinnedVersion = "pinned_version"
    }
}

/// An array decode that survives individual bad elements.
///
/// A local copy of `Catalog`'s helper rather than a shared one: it is internal
/// to that module by design, and the alternative — widening `Catalog`'s public
/// surface so `BrewClient` can borrow thirty lines — trades a real API
/// commitment for a small duplication.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    let skippedCount: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        if let count = container.count { elements.reserveCapacity(count) }
        var skipped = 0

        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                // The container must still advance past the bad element or the
                // loop never terminates. `Skip` accepts any JSON value.
                _ = try? container.decode(Skip.self)
                skipped += 1
            }
        }

        self.elements = elements
        skippedCount = skipped
    }

    /// Consumes exactly one JSON value of any shape and keeps nothing.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {
            _ = try decoder.singleValueContainer()
        }
    }
}
