import Foundation

/// One thing a cask stanza says it will place on the machine.
struct CaskArtifactItemWire: Sendable, Equatable {
    /// What the cask ships, as published — `iTerm.app`.
    let source: String
    /// Where it declares the source goes, when it published a destination.
    let target: String?
}

/// The published `artifacts` list, read for the three stanza kinds this build
/// projects and **counted** for every other kind.
///
/// The counting is the point, not an optimisation. Probe U4 measured that
/// materialising the whole stanza tree costs +28.3 MB resident over 16,214
/// records; the expensive kinds (`zap` alone is +1.23 MB encoded) are directive
/// maps, not name lists. So a key outside `{app, binary, pkg}` increments the
/// counter **from the key alone** — its value is never decoded into a Swift
/// object. What the projection cannot carry, it admits to having counted
/// (catalog-sync T4, package-detail R7).
///
/// Nothing here throws. An unreadable stanza costs a count, never the record.
struct CaskArtifactsWire: Decodable, Sendable {
    let apps: [CaskArtifactItemWire]
    let binaries: [CaskArtifactItemWire]
    let packageInstallers: [CaskArtifactItemWire]
    /// Published stanzas this build does not represent. `0`, never absent, when
    /// every published stanza was represented.
    let unrepresentedStanzaCount: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var apps: [CaskArtifactItemWire] = []
        var binaries: [CaskArtifactItemWire] = []
        var packageInstallers: [CaskArtifactItemWire] = []
        var unrepresented = 0

        while !container.isAtEnd {
            guard let element = try? container.decode(StanzaElementWire.self) else {
                // A list element that is not an object at all — a bare string or
                // number. It published *something*, so it is counted.
                _ = try? container.decode(IgnoredValue.self)
                unrepresented += 1
                continue
            }
            apps.append(contentsOf: element.apps)
            binaries.append(contentsOf: element.binaries)
            packageInstallers.append(contentsOf: element.packageInstallers)
            unrepresented += element.unrepresentedStanzaCount
        }

        self.apps = apps
        self.binaries = binaries
        self.packageInstallers = packageInstallers
        self.unrepresentedStanzaCount = unrepresented
    }
}

/// One element of the `artifacts` list: an object keyed by stanza kind.
///
/// A destination is published two ways — `{"app": ["X.app", {"target": "Y"}]}`
/// and `{"app": ["X.app"], "target": "Y"}` — and both must attach to the
/// element's artifacts rather than count, because `target` is a modifier of a
/// stanza, not a stanza kind of its own.
private struct StanzaElementWire: Decodable {
    let apps: [CaskArtifactItemWire]
    let binaries: [CaskArtifactItemWire]
    let packageInstallers: [CaskArtifactItemWire]
    let unrepresentedStanzaCount: Int

    private static let siblingModifierKey = "target"

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: StanzaKey.self)
        var apps: [CaskArtifactItemWire] = []
        var binaries: [CaskArtifactItemWire] = []
        var packageInstallers: [CaskArtifactItemWire] = []
        var unrepresented = 0

        for key in container.allKeys {
            switch CaskArtifactsWire.ProjectedKind(rawValue: key.stringValue) {
            case .app:
                apps.append(contentsOf: Self.items(in: container, forKey: key))
            case .binary:
                binaries.append(contentsOf: Self.items(in: container, forKey: key))
            case .pkg:
                packageInstallers.append(contentsOf: Self.items(in: container, forKey: key))
            case nil where key.stringValue == Self.siblingModifierKey:
                continue
            case nil:
                // Counted from the key alone: the value is never decoded.
                unrepresented += 1
            }
        }

        let sibling = try? container.decodeIfPresent(String.self, forKey: Self.modifierKey)
        self.apps = Self.applying(sibling ?? nil, to: apps)
        self.binaries = Self.applying(sibling ?? nil, to: binaries)
        self.packageInstallers = Self.applying(sibling ?? nil, to: packageInstallers)
        self.unrepresentedStanzaCount = unrepresented
    }

    private static let modifierKey = StanzaKey(stringValue: siblingModifierKey)!

    private static func items(
        in container: KeyedDecodingContainer<StanzaKey>,
        forKey key: StanzaKey
    ) -> [CaskArtifactItemWire] {
        (try? container.decode(StanzaItemsWire.self, forKey: key))?.items ?? []
    }

    /// A sibling `target` applies to whichever artifact the element published,
    /// and never overrides a destination the item already carried in-array.
    private static func applying(
        _ target: String?,
        to items: [CaskArtifactItemWire]
    ) -> [CaskArtifactItemWire] {
        guard let target else { return items }
        return items.map {
            CaskArtifactItemWire(source: $0.source, target: $0.target ?? target)
        }
    }
}

extension CaskArtifactsWire {
    /// The closed set D5 narrowed the projection to: exactly the stanzas that
    /// answer "what gets installed where".
    enum ProjectedKind: String {
        case app
        case binary
        case pkg
    }
}

/// A stanza's value: a list whose string elements are sources and whose
/// `{"target": …}` objects attach to the source they follow.
private struct StanzaItemsWire: Decodable {
    let items: [CaskArtifactItemWire]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [CaskArtifactItemWire] = []

        while !container.isAtEnd {
            if let source = try? container.decode(String.self) {
                items.append(CaskArtifactItemWire(source: source, target: nil))
            } else if let companion = try? container.decode(StanzaCompanionWire.self),
                      let target = companion.target,
                      let last = items.last {
                items[items.count - 1] = CaskArtifactItemWire(source: last.source, target: target)
            } else {
                // Any other object inside a stanza is a modifier this build does
                // not model. It is skipped without cost: the *stanza* was
                // represented, so it is not part of the remainder.
                _ = try? container.decode(IgnoredValue.self)
            }
        }

        self.items = items
    }
}

/// The `{"target": "…"}` modifier Homebrew emits beside a stanza's sources.
private struct StanzaCompanionWire: Decodable {
    let target: String?
}

/// A key the wire reads by name rather than through a fixed enum, so a stanza or
/// relation kind that did not exist when this build shipped still has a key —
/// which is what lets it be counted instead of dropped.
struct StanzaKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Consumes one element of an unkeyed container without materialising it.
struct IgnoredValue: Decodable {
    init(from decoder: any Decoder) throws {}
}
