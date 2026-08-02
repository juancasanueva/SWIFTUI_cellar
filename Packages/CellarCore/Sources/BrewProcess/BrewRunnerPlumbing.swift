import Foundation

/// The two pieces of `BrewRunner` that hold no runner state.
///
/// Split out when the retention rules (design D6) pushed `BrewRunner.swift`
/// past the 400-line limit. Both are `static` and take everything they need as
/// parameters, so the record dictionary stays `private` to the actor and the
/// projection is still derived in the same file as the state it describes.
extension BrewRunner {
    /// Races the output pump against the grace period on the injected clock.
    ///
    /// The pump finishing is the signal that the process is gone: both the real
    /// and the fake process end their output stream exactly at termination.
    static func completes(
        _ pump: Task<Void, Never>,
        within grace: Duration,
        on clock: any Clock<Duration>
    ) async -> Bool {
        let (outcomes, continuation) = AsyncStream<Bool>.makeStream()

        let watcher = Task.detached {
            await pump.value
            continuation.yield(true)
            continuation.finish()
        }
        let timer = Task.detached {
            try? await clock.sleep(for: grace)
            continuation.yield(false)
            continuation.finish()
        }
        defer {
            watcher.cancel()
            timer.cancel()
        }

        for await outcome in outcomes { return outcome }
        return false
    }

    /// Drains raw chunks into whole, tagged, sequenced lines (design D2).
    static func startPump(
        reading process: any LaunchedProcess,
        into continuation: AsyncStream<LogLine>.Continuation
    ) -> Task<Void, Never> {
        Task {
            var splitter = LineSplitter()
            for await chunk in process.output {
                for line in splitter.consume(chunk) {
                    continuation.yield(line)
                }
            }
            for line in splitter.flush() {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
