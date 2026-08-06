import Foundation

/// The shape both `depends_on` and `conflicts_with` publish: an object keyed by
/// relation kind.
///
/// Same discipline as `CaskArtifactsWire`: the modelled kinds decode into name
/// lists, and every other key is **counted from the key alone** rather than
/// materialised or dropped. `arch`, `java`, `x11` and whatever Homebrew adds
/// next are all one honest number instead of a silent omission (catalog-sync
/// T4). Nothing here throws.
struct CaskRelationsWire: Decodable, Sendable {
    let formulae: [String]
    let casks: [String]
    /// The macOS bound as published, rendered for display — `">= 13"`.
    let macOSRequirement: String?
    /// Relation kinds this build does not model.
    let unrepresentedCount: Int

    private enum ModelledKind: String {
        case formula
        case cask
        case macos
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: StanzaKey.self)
        var formulae: [String] = []
        var casks: [String] = []
        var macOSRequirement: String?
        var unrepresented = 0

        for key in container.allKeys {
            switch ModelledKind(rawValue: key.stringValue) {
            case .formula:
                formulae.append(contentsOf: Self.names(in: container, forKey: key))
            case .cask:
                casks.append(contentsOf: Self.names(in: container, forKey: key))
            case .macos:
                macOSRequirement = try? container.decode(
                    MacOSRequirementWire.self, forKey: key
                ).rendered
            case nil:
                unrepresented += 1
            }
        }

        self.formulae = formulae
        self.casks = casks
        self.macOSRequirement = macOSRequirement
        self.unrepresentedCount = unrepresented
    }

    /// A relation names one package as a bare string or several as a list; both
    /// forms are published.
    private static func names(
        in container: KeyedDecodingContainer<StanzaKey>,
        forKey key: StanzaKey
    ) -> [String] {
        if let list = try? container.decode([String].self, forKey: key) { return list }
        if let single = try? container.decode(String.self, forKey: key) { return [single] }
        return []
    }
}

/// The macOS bound, in either published form: `{">=": ["13"]}` or `[">= :monterey"]`.
private struct MacOSRequirementWire: Decodable {
    let rendered: String

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: StanzaKey.self),
           let key = container.allKeys.first,
           let versions = try? container.decode([String].self, forKey: key),
           !versions.isEmpty {
            rendered = "\(key.stringValue) \(versions.joined(separator: ", "))"
            return
        }
        if var container = try? decoder.unkeyedContainer(),
           let first = try? container.decode(String.self) {
            rendered = first
            return
        }
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            rendered = value
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "no macOS bound published")
        )
    }
}
