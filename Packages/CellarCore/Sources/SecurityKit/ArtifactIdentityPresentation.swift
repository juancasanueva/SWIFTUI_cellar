import Foundation

/// One labelled fact about who signed an artifact.
///
/// A value rather than a formatted string, because the three facts MV-7 compares
/// against `codesign -dv --verbose=4` have to survive into the surface
/// *individually* — an artifact whose identity is rendered as one sentence cannot
/// be compared field by field, and cannot carry one accessibility identifier per
/// field either.
public struct ArtifactIdentityField: Sendable, Hashable, Identifiable {
    /// Stable, distinct per field. Three `Authority` rows must not collapse onto
    /// one identifier — a UI test that queries `…-authority` would then only ever
    /// see the first, and the chain is exactly the part most worth checking.
    public let key: String
    /// Deliberately `codesign`'s own vocabulary, so a human comparing the panel
    /// against `codesign -dv --verbose=4` is reading two copies of the same words
    /// rather than translating between two.
    public let label: String
    public let value: String

    public var id: String { key }

    public init(key: String, label: String, value: String) {
        self.key = key
        self.label = label
        self.value = value
    }
}

extension SecurityPresentation {
    /// Who signed this artifact, field by field.
    ///
    /// Empty for every state that has no identity — unsigned, invalid, and
    /// could-not-assess. Not blank rows: an empty labelled field reads as a fact
    /// about the artifact, and there is no fact there to report.
    ///
    /// The chain is passed through in the platform's own order, **leaf first**.
    /// Sorting or reversing it would make MV-7's literal comparison fail for a
    /// reason that has nothing to do with the artifact.
    public static func identityFields(for signing: ArtifactSigningState) -> [ArtifactIdentityField] {
        switch signing {
        case .signed(let identity):
            var fields = [
                ArtifactIdentityField(
                    key: "identifier",
                    label: "Identifier",
                    value: identity.identifier
                )
            ]
            if let team = identity.teamIdentifier, team.isEmpty == false {
                fields.append(
                    ArtifactIdentityField(key: "team", label: "Team identifier", value: team)
                )
            }
            fields.append(
                contentsOf: identity.authorities.enumerated().map { index, authority in
                    ArtifactIdentityField(
                        key: "authority-\(index)",
                        label: "Authority",
                        value: authority
                    )
                }
            )
            return fields

        case .adHoc(let identifier):
            // Every brew bottle is here. An ad-hoc signature has a real
            // identifier and genuinely no team and no chain — the U3 probe
            // measured exactly that on `rg`. Showing the identifier is honest;
            // showing an empty team would invent one.
            return [
                ArtifactIdentityField(key: "identifier", label: "Identifier", value: identifier)
            ]

        case .unsigned, .invalid, .couldNotAssess:
            return []
        }
    }

    /// The house accessibility scheme, composed here so the view does not spell
    /// it — `security-integrity-{package}` is the row, and each field hangs off it.
    public static func identityFieldIdentifier(
        _ field: ArtifactIdentityField,
        package: String
    ) -> String {
        "security-integrity-\(package)-\(field.key)"
    }
}
