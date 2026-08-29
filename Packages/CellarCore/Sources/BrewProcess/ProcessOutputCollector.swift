import Foundation

/// Drains a directly-spawned process into whole lines and its terminal result.
///
/// Two callers spawn without a `BrewRunner` — the locators, which validate the
/// binary the runner would need, and npm's read payload source, whose two
/// commands need none of the runner's FIFO, cancel escalation or retention.
/// Each of them was reproducing the same six lines, and the ordering in them is
/// not incidental: **output is drained to completion before the exit is asked
/// for**, which is the runner's own contract. Getting that backwards yields a
/// result whose last lines are missing, intermittently and only under load.
///
/// It exists so `LineSplitter` can stay internal to this target. Line splitting
/// is a pipe-level concern, and a client that reassembles partial lines itself
/// is a client that will eventually reassemble them differently.
public enum ProcessOutputCollector {
    /// Every line the process wrote, then how it ended.
    public static func drain(
        _ process: any LaunchedProcess
    ) async -> (lines: [LogLine], exit: BrewExit) {
        var splitter = LineSplitter()
        var lines: [LogLine] = []
        for await chunk in process.output {
            lines.append(contentsOf: splitter.consume(chunk))
        }
        lines.append(contentsOf: splitter.flush())
        return (lines, await process.waitForTermination())
    }
}
