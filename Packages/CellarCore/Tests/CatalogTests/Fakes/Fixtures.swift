import Foundation
import Testing

/// Access to the live payload excerpts captured in `Tests/CatalogTests/Fixtures`.
///
/// See `Fixtures/README.md` for what each file is and how to re-capture it.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    /// The single-package endpoints return one object; the bulk endpoints return
    /// an array. Tests that exercise the array decoder wrap the single records.
    static func wrappedInArray(_ name: String) throws -> Data {
        let record = try data(name)
        var wrapped = Data("[".utf8)
        wrapped.append(record)
        wrapped.append(Data("]".utf8))
        return wrapped
    }

    /// Several single-record fixtures joined into one bulk-endpoint payload.
    static func arrayOf(_ names: [String]) throws -> Data {
        var payload = Data("[".utf8)
        for (offset, name) in names.enumerated() {
            if offset > 0 { payload.append(Data(",".utf8)) }
            payload.append(try data(name))
        }
        payload.append(Data("]".utf8))
        return payload
    }

    /// The fixtures the widened cask/formula inspection projection is specified
    /// against, registered in one place so a file that is added to the directory
    /// but never copied into the bundle fails loudly here rather than as a
    /// mystery `#require` failure inside whichever test happened to load it.
    ///
    /// See `Fixtures/README.md` for what each one exercises.
    static let inspectionFixtures = [
        "cask-every-stanza",
        "cask-unrepresented",
        "cask-only-unrepresented",
        "cask-bare",
        "cask-bare-null",
        "cask-no-check",
        "formula-headless"
    ]

    /// The discovery fixtures live one directory deeper, so the curated-list and
    /// sidecar shapes stay visibly separate from the payload excerpts they have
    /// nothing to do with.
    static func discovery(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures/Discovery"
            ),
            "missing discovery fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    /// Registered for the same reason `inspectionFixtures` is: a file added to
    /// `Fixtures/Discovery/` but never copied into the bundle fails here, once,
    /// rather than as a mystery `#require` failure inside whichever suite
    /// happened to load it first.
    ///
    /// See `Fixtures/README.md` for what each one exercises.
    static let discoveryFixtures = [
        "curated-tolerant",
        "curated-duplicate",
        "curated-unsorted",
        "roster-corrupt",
        "roster-wrong-version",
        "arrivals-corrupt",
        "arrivals-wrong-version",
        "arrivals-undatable"
    ]
}
