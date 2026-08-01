import Foundation

/// The subset of a published formula record the projection keeps.
///
/// Declaring only these keys is what makes the 31 MB dump decode into a few
/// megabytes: every unmodelled key is skipped by the parser rather than
/// materialised and then thrown away (design D8). It is also, for free, the
/// "unknown keys are ignored" guarantee (catalog-sync CS5).
///
/// Every field the payload may publish as `null` is `decodeIfPresent`, so an
/// absent description stays absent instead of collapsing into `""`.
struct FormulaWire: Decodable, Sendable {
    let name: String
    let tap: String?
    let desc: String?
    let license: String?
    let homepage: String?
    let versions: Versions?
    let dependencies: [String]?
    let buildDependencies: [String]?
    let usesFromMacos: [UsesFromMacOS]?
    let caveats: String?
    let deprecated: Bool?
    let deprecationReason: String?
    let deprecationDate: String?
    let disabled: Bool?
    let disableReason: String?
    let disableDate: String?

    /// Synthesised on purpose: an optional stored property already decodes as
    /// "absent or null", which is exactly the tolerance this needs.
    struct Versions: Decodable, Sendable {
        let stable: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        tap = try container.decodeIfPresent(String.self, forKey: .tap)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        versions = try container.decodeIfPresent(Versions.self, forKey: .versions)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies)
        buildDependencies = try container.decodeIfPresent([String].self, forKey: .buildDependencies)
        usesFromMacos = try container.decodeIfPresent([UsesFromMacOS].self, forKey: .usesFromMacos)
        caveats = try container.decodeIfPresent(String.self, forKey: .caveats)
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated)
        deprecationReason = try container.decodeIfPresent(String.self, forKey: .deprecationReason)
        deprecationDate = try container.decodeIfPresent(String.self, forKey: .deprecationDate)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        disableReason = try container.decodeIfPresent(String.self, forKey: .disableReason)
        disableDate = try container.decodeIfPresent(String.self, forKey: .disableDate)
    }

    enum CodingKeys: String, CodingKey {
        case name, tap, desc, license, homepage, versions, dependencies, caveats
        case deprecated, disabled
        case buildDependencies = "build_dependencies"
        case usesFromMacos = "uses_from_macos"
        case deprecationReason = "deprecation_reason"
        case deprecationDate = "deprecation_date"
        case disableReason = "disable_reason"
        case disableDate = "disable_date"
    }
}
