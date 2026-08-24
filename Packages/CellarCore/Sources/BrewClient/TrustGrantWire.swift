import Foundation

/// What Homebrew reports about **per-package** trust grants.
///
/// Three-valued for exactly the reason `TapTrustState` is: a Homebrew that
/// cannot answer `brew trust --json v1` is `unreported`, which is **not** the
/// same fact as a Homebrew answering with an empty ledger (package-trust PT1
/// :62-73). A boolean, or a bare count, would report every such Mac as having
/// zero grants — a fact about this machine nobody measured.
public enum TrustGrantState: Sendable, Equatable {
    case granted(TrustGrantLedger)
    /// brew answered, and its answer carried no entry at all.
    case noGrants
    /// brew did not answer: no `trust` verb, a failed spawn, or a payload that
    /// did not decode.
    case unreported

    /// The only way to build a reported state, so `granted` can never carry a
    /// ledger with nothing in it and the two reported cases cannot both mean
    /// "nothing" (DD-1).
    public static func reported(_ ledger: TrustGrantLedger) -> TrustGrantState {
        ledger.isEmpty ? .noGrants : .granted(ledger)
    }

    /// What a settled read leaves behind.
    ///
    /// A failure keeps the **last good** report rather than replacing it with an
    /// empty one (PT2 :141-147), so a transient failure cannot silently
    /// downgrade a real count to "nothing". On a machine that has never had a
    /// good answer the last good value is `unreported`, which is the honest one.
    public static func settled(
        _ outcome: Result<TrustGrantLedger, TrustGrantError>,
        keeping lastGood: TrustGrantState
    ) -> TrustGrantState {
        switch outcome {
        case .success(let ledger): reported(ledger)
        case .failure: lastGood
        }
    }

    /// The decoded report, or `nil` when there is none to read.
    ///
    /// `noGrants` and `unreported` both answer `nil` on purpose: neither carries
    /// entries, and the difference between them is a fact about the *report*,
    /// which the copy states (PT6 :366-373), not a fact about any package.
    public var ledger: TrustGrantLedger? {
        guard case .granted(let ledger) = self else { return nil }
        return ledger
    }

    /// How many entries brew reported, or `nil` when it reported nothing at all.
    ///
    /// Optional rather than `0` for `unreported`: "no answer" and "an answer of
    /// zero" are different, and collapsing them here would put the count back in
    /// the one place PT1 forbids it.
    public var entryCount: Int? {
        switch self {
        case .granted(let ledger): ledger.entryCount
        case .noGrants: 0
        case .unreported: nil
        }
    }
}

/// Grant entries exactly as Homebrew published them — fully qualified, never
/// normalized here. Normalization is attribution's job (DD-5), and doing it at
/// the wire would destroy the one property attribution depends on: a URL-shaped
/// `formulae` entry is a real entry that no positional split can read.
public struct TrustGrantLedger: Sendable, Equatable {
    public let formulae: [String]
    public let casks: [String]
    /// Decoded so nothing is dropped, and **never consumed** as a trust state: a
    /// tap's own grant comes from `tap-info` alone (tap-management TM12, DD-9).
    /// It exists here so a grant for a tap that is no longer installed can be
    /// shown as an orphan rather than vanishing (PT8).
    public let taps: [String]
    /// The namespace Cellar has no other concept for. Counted as "other".
    public let commands: [String]
    /// Top-level keys this capability does not model, kept verbatim and keyed by
    /// their published name.
    ///
    /// Forward compatibility that *discarded* them would make the accounting's
    /// "these totals sum to the entries decoded" claim quietly false the day
    /// Homebrew publishes a fifth namespace (PT4 :270-276).
    public let unmodelled: [String: [String]]
    /// Which top-level keys the payload actually carried.
    ///
    /// A namespace present with an empty array is a report of nothing in it,
    /// which PT4 :262-268 requires to stay distinguishable from a namespace
    /// nobody sent — and an empty array cannot carry that distinction itself.
    public let declaredNamespaces: Set<String>

    public init(
        formulae: [String] = [],
        casks: [String] = [],
        taps: [String] = [],
        commands: [String] = [],
        unmodelled: [String: [String]] = [:],
        declaredNamespaces: Set<String>? = nil
    ) {
        self.formulae = formulae
        self.casks = casks
        self.taps = taps
        self.commands = commands
        self.unmodelled = unmodelled
        // A synthesised ledger declares the namespaces it actually carries; the
        // decoder passes the payload's real key set instead.
        self.declaredNamespaces = declaredNamespaces ?? Self.carrying(
            formulae: formulae,
            casks: casks,
            taps: taps,
            commands: commands,
            unmodelled: unmodelled
        )
    }

    /// Whether the payload carried a `commands` key at all.
    public var declaresCommands: Bool { declaredNamespaces.contains(Namespace.commands) }

    /// Every entry brew published, across every namespace including the ones
    /// this capability does not model.
    public var entryCount: Int {
        formulae.count + casks.count + taps.count + commands.count
            + unmodelled.values.reduce(0) { $0 + $1.count }
    }

    /// Whether brew reported nothing at all.
    ///
    /// **Deliberately not package-scoped.** The design's first draft ignored
    /// `taps` here, on the reasoning that a tap grant is not a package grant.
    /// The corrected spec makes an **orphan tap grant** its own accounted and
    /// *shown* category (PT4 :219-244, PT8 :423-441), so a ledger carrying only
    /// a `taps` entry has something to show; collapsing it into `noGrants` would
    /// drop a decoded entry silently, which is the one thing PT4 forbids
    /// outright. Package-scoped emptiness is expressed where it belongs — as a
    /// count of zero *attributed* grants, which renders no count line (DD-7).
    public var isEmpty: Bool { entryCount == 0 }

    /// The four namespaces Homebrew publishes and this capability models.
    enum Namespace {
        static let taps = "taps"
        static let formulae = "formulae"
        static let casks = "casks"
        static let commands = "commands"

        static let modelled: Set<String> = [taps, formulae, casks, commands]
    }

    private static func carrying(
        formulae: [String],
        casks: [String],
        taps: [String],
        commands: [String],
        unmodelled: [String: [String]]
    ) -> Set<String> {
        var declared = Set(unmodelled.keys)
        if !formulae.isEmpty { declared.insert(Namespace.formulae) }
        if !casks.isEmpty { declared.insert(Namespace.casks) }
        if !taps.isEmpty { declared.insert(Namespace.taps) }
        if !commands.isEmpty { declared.insert(Namespace.commands) }
        return declared
    }
}

public enum TrustGrantError: Error, Sendable, Equatable {
    case brewUnavailable
    case commandFailed(status: Int32, message: String)
    case blankOutput
    case malformedJSON
    case nonObjectEnvelope
    case cancelled
}

public enum TrustGrantDecoder {
    @concurrent
    public static func decode(_ data: Data) async throws(TrustGrantError) -> TrustGrantLedger {
        try ledger(from: data)
    }

    static func ledger(from data: Data) throws(TrustGrantError) -> TrustGrantLedger {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .malformedJSON
        }
        guard object is [String: Any] else { throw .nonObjectEnvelope }

        let wire: TrustGrantWire
        do {
            wire = try JSONDecoder().decode(TrustGrantWire.self, from: data)
        } catch {
            throw .malformedJSON
        }

        let namespaces = wire.namespaces
        return TrustGrantLedger(
            formulae: namespaces[TrustGrantLedger.Namespace.formulae] ?? [],
            casks: namespaces[TrustGrantLedger.Namespace.casks] ?? [],
            taps: namespaces[TrustGrantLedger.Namespace.taps] ?? [],
            commands: namespaces[TrustGrantLedger.Namespace.commands] ?? [],
            unmodelled: namespaces.filter {
                !TrustGrantLedger.Namespace.modelled.contains($0.key)
            },
            declaredNamespaces: Set(namespaces.keys)
        )
    }
}

/// The payload as a set of named grant lists, read through a **dynamic-key**
/// container so a namespace this capability does not model is retained instead
/// of being dropped by a fixed `CodingKeys` enum (PT4 :270-276).
private struct TrustGrantWire: Decodable {
    let namespaces: [String: [String]]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        namespaces = container.allKeys.reduce(into: [:]) { namespaces, key in
            // A key whose value is not a list of strings is not a grant
            // namespace: it carries no entry, so there is nothing to count and
            // nothing is lost by leaving it alone. A key that *is* a list of
            // strings is kept whole, whatever it is called.
            guard let entries = try? container.decode([String].self, forKey: key) else { return }
            namespaces[key.stringValue] = entries
        }
    }
}
