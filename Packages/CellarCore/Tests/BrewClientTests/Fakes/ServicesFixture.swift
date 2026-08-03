import Foundation

/// Canned `brew services` payloads.
///
/// **Fixture-first is mandatory here, and it is not a convenience.** The
/// development machine has exactly one Homebrew service (`atuin`) and it can
/// only be observed in two of the seven states brew can report — `none` and,
/// by starting it, `started`. `scheduled`, `stopped`, `error`, `unknown` and
/// `other` are not producible on this machine at all, so a live probe cannot be
/// the primary evidence for the decoder. These payloads are.
///
/// Every shape below was taken from a real probe (brew 6.0.14, 2026-08-03) and
/// then widened. Two details are load-bearing and would not survive being
/// "tidied up":
///
/// - optional keys in both payloads are emitted as **JSON null**, never omitted;
/// - `log_path` and `error_log_path` really are the same file on this machine,
///   which is why the dedupe rule exists rather than being hypothetical.
enum ServicesFixture {
    // MARK: - `brew services list --json`

    /// One record per status brew's `status_symbol` can produce.
    static let allStatuses = list(
        [
            record(name: "started-one", status: "started", user: "\"tester\"", exitCode: "null"),
            record(name: "none-one", status: "none"),
            record(name: "scheduled-one", status: "scheduled"),
            record(name: "stopped-one", status: "stopped"),
            record(name: "error-one", status: "error", user: "\"tester\"", exitCode: "1"),
            record(name: "unknown-one", status: "unknown"),
            record(name: "other-one", status: "other")
        ]
    )

    /// Three records, the last carrying a status string brew does not publish
    /// today. A future brew adding an eighth symbol must cost that symbol's
    /// label, never the other two records.
    static let withUnrecognisedStatus = list(
        [
            record(name: "atuin", status: "started"),
            record(name: "postgresql", status: "none"),
            record(name: "enigma", status: "mystery")
        ]
    )

    /// The stopped-service shape exactly as probed: `user` and `exit_code` both
    /// null, not absent.
    static let withNullUserAndExitCode = list([record(name: "atuin", status: "none")])

    /// One good record and one that cannot be decoded at all — its `name` is
    /// missing, which is the shape a published record drifting would take. The
    /// good one must still arrive.
    static let withUndecodableRecord = """
        [
          {"name":"atuin","status":"started","user":"tester",\
        "file":"/opt/homebrew/opt/atuin/homebrew.mxcl.atuin.plist","exit_code":null},
          {"status":"none","user":null,"exit_code":null}
        ]
        """

    /// Not an array at the top level. Nothing in it is recoverable.
    static let notAList = "{\"services\":[]}"

    // MARK: - `brew services info --json <name>`

    /// The probed stopped-service detail: `pid`, `user`, `loaded_file`,
    /// `working_dir`, `root_dir`, `interval` and `cron` all null, and **both**
    /// log locations null too.
    static let infoWithNullOptionalKeys = info(
        name: "atuin",
        logPath: "null",
        errorLogPath: "null"
    )

    /// The live shape on the development machine: one file, named twice.
    static let infoWithIdenticalLogPaths = info(
        name: "atuin",
        logPath: "\"/opt/homebrew/var/log/atuin.log\"",
        errorLogPath: "\"/opt/homebrew/var/log/atuin.log\""
    )

    /// The same service configured to separate its streams.
    static let infoWithDistinctLogPaths = info(
        name: "atuin",
        logPath: "\"/opt/homebrew/var/log/atuin.log\"",
        errorLogPath: "\"/opt/homebrew/var/log/atuin.error.log\"",
        pid: "4242",
        user: "\"tester\""
    )

    // MARK: - Builders

    static func list(_ records: [String]) -> String {
        "[\(records.joined(separator: ","))]"
    }

    static func record(
        name: String,
        status: String,
        user: String = "null",
        exitCode: String = "null",
        file: String? = nil
    ) -> String {
        let plist = file ?? "/opt/homebrew/opt/\(name)/homebrew.mxcl.\(name).plist"
        return """
            {"name":"\(name)","status":"\(status)","user":\(user),\
            "file":"\(plist)","exit_code":\(exitCode)}
            """
    }

    static func info(
        name: String,
        status: String = "none",
        logPath: String,
        errorLogPath: String,
        pid: String = "null",
        user: String = "null"
    ) -> String {
        """
        [{"name":"\(name)","service_name":"homebrew.mxcl.\(name)","running":false,\
        "loaded":false,"schedulable":false,"pid":\(pid),"exit_code":null,"user":\(user),\
        "status":"\(status)","file":"/opt/homebrew/opt/\(name)/homebrew.mxcl.\(name).plist",\
        "registered":false,"loaded_file":null,\
        "command":"/opt/homebrew/opt/\(name)/bin/\(name) daemon start",\
        "working_dir":null,"root_dir":null,"log_path":\(logPath),\
        "error_log_path":\(errorLogPath),"interval":null,"cron":null}]
        """
    }
}
