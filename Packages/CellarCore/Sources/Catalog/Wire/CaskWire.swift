import Foundation

/// The subset of a published cask record the projection keeps.
///
/// The cask schema differs from the formula schema in three ways that matter:
/// the token lives in `token` (not `name`), `name` is an **array** of
/// human-readable names — often multilingual, e.g.
/// `["115Browser", "115浏览器"]` — and `version` is a bare string rather than a
/// `versions` object (catalog-sync CS5).
///
/// The key subset widened once, for M5 pre-install inspection: `url`, `sha256`,
/// `artifacts`, `depends_on` and `conflicts_with`. Nothing else about the
/// strategy changed — every one of the five is `decodeIfPresent`, so the D8
/// discipline that makes a 17 MB dump decode into megabytes still holds, and a
/// record publishing none of them costs nothing.
///
/// Two properties of the widening are load-bearing and easy to break:
///
/// * A record that publishes one of the five in a shape this build cannot read
///   keeps every other field and reports that one absent. The widening MUST NOT
///   change which records decode (catalog-sync T5), which is why the five are
///   read with `try?` while everything above them uses `try`.
/// * `artifacts` reads only the stanza kinds the projection represents and
///   *counts* the rest from the key alone. See `CaskArtifactsWire`.
///
/// The persisted projection this feeds is at `schemaVersion` 2; the widening is
/// what moved it off 1.
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
    // The inspection subset (M5). Each is `decodeIfPresent` for the same reason
    // every key above is: a cask that omits it, and a cask that publishes it as
    // `null`, are the same answer — absent — and neither costs the record.
    let url: String?
    let sha256: String?
    let artifacts: CaskArtifactsWire?
    let dependsOn: CaskRelationsWire?
    let conflictsWith: CaskRelationsWire?

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
        // `try?` and not `try` on all five: the widening must not change which
        // records decode (catalog-sync T5). A record that publishes one of these
        // in a shape this build cannot read keeps every field it already had and
        // reports that one absent, exactly as if it had been omitted. Only the
        // pre-existing keys above may cost a record.
        url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? nil
        sha256 = (try? container.decodeIfPresent(String.self, forKey: .sha256)) ?? nil
        artifacts = (try? container.decodeIfPresent(CaskArtifactsWire.self, forKey: .artifacts))
            ?? nil
        dependsOn = (try? container.decodeIfPresent(CaskRelationsWire.self, forKey: .dependsOn))
            ?? nil
        conflictsWith = (
            try? container.decodeIfPresent(CaskRelationsWire.self, forKey: .conflictsWith)
        ) ?? nil
    }

    enum CodingKeys: String, CodingKey {
        case token, name, tap, desc, homepage, version, caveats, deprecated, disabled
        case url, sha256, artifacts
        case dependsOn = "depends_on"
        case conflictsWith = "conflicts_with"
        case autoUpdates = "auto_updates"
        case deprecationReason = "deprecation_reason"
        case deprecationDate = "deprecation_date"
        case disableReason = "disable_reason"
        case disableDate = "disable_date"
    }
}
