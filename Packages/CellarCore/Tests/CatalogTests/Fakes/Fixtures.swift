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
}
