import Foundation

/// Everything that can go wrong acquiring or reading a services payload.
///
/// Closed for the same reason `InstalledInventoryError` is: the store has to
/// decide, per case, whether the last good list survives. An open error type
/// makes that decision impossible to review.
///
/// Declared here rather than beside the payload sources because the decoder
/// below is the first thing that needs it, and every commit in this slice has
/// to compile on its own.
public enum ServicesError: Error, Sendable, Equatable {
    /// There is no usable `brew` to ask. Guidance, not failure.
    case brewUnavailable
    /// `brew` ran and returned non-zero. `message` is the tail of its stderr.
    case commandFailed(status: Int32, message: String)
    /// `brew` returned something that is not the documented payload.
    case malformedPayload
    /// The refresh was cancelled. Not a failure (`BrewProcess` D3).
    case cancelled
}

/// What `brew` says a service is doing.
///
/// The seven cases are brew's own vocabulary, verified from
/// `services/formula_wrapper.rb`'s `status_symbol` rather than from
/// observation: only `none` is reachable on the development machine.
///
/// `unrecognised` is the catch-all, and it cannot be named `other` — because
/// `other` is one of the seven real values. An eighth symbol added by a future
/// brew must cost that symbol's label and nothing else, so the raw string is
/// carried rather than discarded (service-management SM1).
public enum ServiceStatus: Sendable, Equatable, Hashable {
    case started
    case none
    case scheduled
    case stopped
    case error
    case unknown
    case other
    /// A status string this build does not know. Never an error.
    case unrecognised(String)

    /// brew's seven, keyed by the string it emits.
    private static let known: [String: ServiceStatus] = [
        "started": .started,
        "none": .none,
        "scheduled": .scheduled,
        "stopped": .stopped,
        "error": .error,
        "unknown": .unknown,
        "other": .other
    ]

    public init(raw: String) {
        self = Self.known[raw] ?? .unrecognised(raw)
    }

    /// The string brew emitted, whichever case this is.
    public var raw: String {
        switch self {
        case .started: "started"
        case .none: "none"
        case .scheduled: "scheduled"
        case .stopped: "stopped"
        case .error: "error"
        case .unknown: "unknown"
        case .other: "other"
        case .unrecognised(let raw): raw
        }
    }

    /// Whether brew is reporting this service as broken.
    ///
    /// Deliberately not "is it running": `unrecognised` is not a failure, it is
    /// a status this build cannot name, and colouring it red would tell the
    /// user something brew never said.
    public var isFailure: Bool {
        switch self {
        case .error, .unknown: true
        case .started, .none, .scheduled, .stopped, .other, .unrecognised: false
        }
    }
}

/// One row of `brew services list --json`.
///
/// Trimmed to what the list surface reads, on `InstalledWire`'s discipline: the
/// keys that are never rendered are never projected.
public struct ServiceRecord: Sendable, Equatable, Identifiable, Hashable {
    /// The service's own identity. **Not** a `PackageID`: a service that shares
    /// a name with an installed formula is not that formula, and the two are
    /// never derived from each other (SM12).
    public var id: String { name }

    public let name: String
    public let status: ServiceStatus
    /// The user launchd runs it as, when brew reports one. Null means absent.
    public let user: String?
    /// The last exit status brew observed, when it observed one.
    public let exitCode: Int?
    /// The plist brew installed for it.
    public let plistPath: URL?

    public init(
        name: String,
        status: ServiceStatus,
        user: String? = nil,
        exitCode: Int? = nil,
        plistPath: URL? = nil
    ) {
        self.name = name
        self.status = status
        self.user = user
        self.exitCode = exitCode
        self.plistPath = plistPath
    }
}

/// One record of `brew services info --json <name>`.
public struct ServiceDetail: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { name }

    public let name: String
    public let status: ServiceStatus
    public let user: String?
    public let pid: Int?
    public let plistPath: URL?

    /// Where to read this service's output, **deduped and order-stable**.
    ///
    /// brew emits `log_path` and `error_log_path` separately and they are
    /// frequently the same file — they are on the development machine right
    /// now. Offering one file as two locations would invite the user to open
    /// the same window twice. The ordinary log comes first; the error log
    /// follows only when it is a different file. A service declaring neither
    /// reports none, never an empty or placeholder path (SM2).
    public let logPaths: [URL]

    public init(
        name: String,
        status: ServiceStatus,
        user: String? = nil,
        pid: Int? = nil,
        plistPath: URL? = nil,
        logPaths: [URL] = []
    ) {
        self.name = name
        self.status = status
        self.user = user
        self.pid = pid
        self.plistPath = plistPath
        self.logPaths = logPaths
    }

    /// Folds the two declared log locations into the list the UI shows.
    ///
    /// A free function over two optionals rather than a step inside the
    /// decoder: the rule is the whole of SM2's dedupe clause, and this way it
    /// is provable without a payload at all.
    static func logPaths(log: String?, errorLog: String?) -> [URL] {
        var paths: [URL] = []
        for candidate in [log, errorLog] {
            guard let candidate, !candidate.isEmpty else { continue }
            let url = URL(fileURLWithPath: candidate)
            guard !paths.contains(url) else { continue }
            paths.append(url)
        }
        return paths
    }
}

// MARK: - Wire

/// One `services list --json` element.
///
/// `name` and `status` are required — a record carrying neither is not a
/// service record. Everything else is optional, and arrives as JSON **null**
/// rather than absent, which decodes to `nil` either way.
private struct ServiceRecordWire: Decodable {
    let name: String
    let status: String
    let user: String?
    let file: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case name, status, user, file
        case exitCode = "exit_code"
    }
}

/// One `services info --json` element.
///
/// The probed payload carries eighteen keys; the twelve this surface never
/// renders — `service_name`, `running`, `loaded`, `schedulable`, `registered`,
/// `loaded_file`, `command`, `working_dir`, `root_dir`, `interval`, `cron`,
/// `exit_code` — are deliberately not projected.
private struct ServiceDetailWire: Decodable {
    let name: String
    let status: String
    let user: String?
    let pid: Int?
    let file: String?
    let logPath: String?
    let errorLogPath: String?

    enum CodingKeys: String, CodingKey {
        case name, status, user, pid, file
        case logPath = "log_path"
        case errorLogPath = "error_log_path"
    }
}

/// Turns services payloads into projections.
///
/// A pure function over `Data`, mirroring `InstalledDecoder`: no process, no
/// file system, no clock, so every shape a payload can take is reachable from a
/// test — which is the only way six of the seven statuses are reachable at all.
public enum ServicesDecoder {
    /// Decodes a list payload off the caller's executor.
    ///
    /// `@concurrent` before the modifier, like `InstalledDecoder.decode` — the
    /// other order does not compile. The caller is the main actor and the
    /// result is `Sendable` by composition.
    @concurrent
    public static func decode(_ data: Data) async throws(ServicesError) -> [ServiceRecord] {
        try services(from: data)
    }

    /// Decodes a detail payload off the caller's executor.
    @concurrent
    public static func decodeDetails(
        _ data: Data
    ) async throws(ServicesError) -> [ServiceDetail] {
        try details(from: data)
    }

    /// The list projection.
    ///
    /// Threat response — **untrusted subprocess payload**: a document that is
    /// not a list is `.malformedPayload`, because nothing in it is recoverable;
    /// a single unreadable *record* costs that record only, because one service
    /// whose shape drifted must not empty the user's list.
    static func services(from data: Data) throws(ServicesError) -> [ServiceRecord] {
        try decodeArray(data, of: ServiceRecordWire.self).map { wire in
            ServiceRecord(
                name: wire.name,
                status: ServiceStatus(raw: wire.status),
                user: wire.user,
                exitCode: wire.exitCode,
                plistPath: path(wire.file)
            )
        }
    }

    /// The detail projection, with the log dedupe applied.
    static func details(from data: Data) throws(ServicesError) -> [ServiceDetail] {
        try decodeArray(data, of: ServiceDetailWire.self).map { wire in
            ServiceDetail(
                name: wire.name,
                status: ServiceStatus(raw: wire.status),
                user: wire.user,
                pid: wire.pid,
                plistPath: path(wire.file),
                logPaths: ServiceDetail.logPaths(log: wire.logPath, errorLog: wire.errorLogPath)
            )
        }
    }

    private static func decodeArray<Element: Decodable>(
        _ data: Data,
        of element: Element.Type
    ) throws(ServicesError) -> [Element] {
        do {
            // `LossyArray` is what makes one bad element cost one element.
            return try JSONDecoder().decode(LossyArray<Element>.self, from: data).elements
        } catch {
            throw .malformedPayload
        }
    }

    private static func path(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(fileURLWithPath: string)
    }
}
