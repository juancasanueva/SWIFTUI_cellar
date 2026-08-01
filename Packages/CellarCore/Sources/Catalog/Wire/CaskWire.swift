import Foundation

/// The subset of a published cask record the projection keeps.
///
/// The cask schema differs from the formula schema in three ways that matter:
/// the token lives in `token` (not `name`), `name` is an **array** of
/// human-readable names — often multilingual, e.g.
/// `["115Browser", "115浏览器"]` — and `version` is a bare string rather than a
/// `versions` object (catalog-sync CS5).
struct CaskWire: Decodable, Sendable {
    let token: String
    let name: [String]?
    let tap: String?
    let desc: String?
    let homepage: String?
    let version: String?
    let caveats: String?
    let autoUpdates: Bool?
    let deprecated: Bool?
    let deprecationReason: String?
    let deprecationDate: String?
    let disabled: Bool?
    let disableReason: String?
    let disableDate: String?

    /// What a human calls it: the first published name, falling back to the
    /// install token when the array is missing or empty.
    var displayName: String {
        name?.first(where: { !$0.isEmpty }) ?? token
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        name = try container.decodeIfPresent([String].self, forKey: .name)
        tap = try container.decodeIfPresent(String.self, forKey: .tap)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        caveats = try container.decodeIfPresent(String.self, forKey: .caveats)
        autoUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoUpdates)
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated)
        deprecationReason = try container.decodeIfPresent(String.self, forKey: .deprecationReason)
        deprecationDate = try container.decodeIfPresent(String.self, forKey: .deprecationDate)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        disableReason = try container.decodeIfPresent(String.self, forKey: .disableReason)
        disableDate = try container.decodeIfPresent(String.self, forKey: .disableDate)
    }

    enum CodingKeys: String, CodingKey {
        case token, name, tap, desc, homepage, version, caveats, deprecated, disabled
        case autoUpdates = "auto_updates"
        case deprecationReason = "deprecation_reason"
        case deprecationDate = "deprecation_date"
        case disableReason = "disable_reason"
        case disableDate = "disable_date"
    }
}
