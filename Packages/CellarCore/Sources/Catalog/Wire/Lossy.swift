import Foundation

/// An array decode that survives individual bad elements.
///
/// The published dumps carry ~16,000 records written by many contributors. A
/// single record whose shape drifted must cost that record and nothing else —
/// the alternative is a whole catalog that vanishes because one formula grew a
/// `null` where a string used to be (catalog-sync CS5, design D6).
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

/// One `uses_from_macos` entry, which the payload writes either as a bare name
/// or as a single-key object mapping that name to a build/test bound.
///
/// The bound itself is published as a string (`"build"`) *or* an array
/// (`["build"]`) depending on the formula, so it is decoded permissively and
/// then discarded: the projection only needs the name.
enum UsesFromMacOS: Decodable, Hashable, Sendable {
    case bare(String)
    case bounded(name: String, bounds: [String])

    var name: String {
        switch self {
        case .bare(let name): name
        case .bounded(let name, _): name
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self = .bare(name)
            return
        }
        let object = try container.decode([String: Bound].self)
        guard let (name, bound) = object.first else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "uses_from_macos object had no key"
            )
        }
        self = .bounded(name: name, bounds: bound.values)
    }

    /// `"build"` and `["build"]` are the same fact written two ways.
    private struct Bound: Decodable {
        let values: [String]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                values = [single]
            } else {
                values = (try? container.decode([String].self)) ?? []
            }
        }
    }
}
