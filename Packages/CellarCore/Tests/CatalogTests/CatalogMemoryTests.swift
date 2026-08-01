import Darwin
import Foundation
import Synchronization
import Testing

@testable import Catalog

/// The 40 MB decode is the single biggest memory risk in this milestone, so it
/// carries a measured ceiling rather than a comment (design D8).
///
/// The payload is generated into a temp directory on every run — it is 40 MB and
/// must never enter the repository.
@Suite("Decode memory budget", .serialized)
struct CatalogMemoryTests {
    static let peakBudget = 300 * 1_048_576
    static let retainedBudget = 40 * 1_048_576

    @Test("Decoding a 40 MB payload stays inside the peak and retained budgets", .timeLimit(.minutes(2)))
    func decodeStaysInsideTheMemoryBudget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-catalog-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = directory.appendingPathComponent("formula.json")
        let writtenBytes = try SyntheticPayload.writeFormulae(to: payload, targetBytes: 40 * 1_048_576)
        #expect(writtenBytes >= 40 * 1_048_576)

        let baseline = MemoryProbe.physFootprint()
        let sampler = MemoryProbe.Sampler()
        sampler.start()
        let decoded = try CatalogDecoder.decodeFormulae(contentsOf: payload)
        let peak = sampler.stop()
        let retained = MemoryProbe.physFootprint()

        // The decode really happened: a trivial pass would report zero records.
        #expect(decoded.packages.count > 5_000)
        #expect(decoded.packages[0].tap == "homebrew/core")

        let peakDelta = Int(peak) - Int(baseline)
        let retainedDelta = Int(retained) - Int(baseline)
        #expect(
            peakDelta <= Self.peakBudget,
            "peak grew \(peakDelta / 1_048_576) MB, budget \(Self.peakBudget / 1_048_576) MB"
        )
        #expect(
            retainedDelta <= Self.retainedBudget,
            "retained \(retainedDelta / 1_048_576) MB, budget \(Self.retainedBudget / 1_048_576) MB"
        )
    }

    @Test("A staged payload is deleted as soon as it has been projected")
    func stagedPayloadIsDeletedAfterProjection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-catalog-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = directory.appendingPathComponent("formula.json")
        try Data(#"""
        [{"name":"wget","tap":"homebrew/core","desc":"Internet file retriever",
          "versions":{"stable":"1.25.0"}}]
        """#.utf8).write(to: payload)

        let decoded = try CatalogDecoder.decodeFormulae(contentsOf: payload, deletingAfterwards: true)

        #expect(decoded.packages.map(\.name) == ["wget"])
        #expect(FileManager.default.fileExists(atPath: payload.path) == false)
    }
}

/// Writes a realistic formula dump straight to disk, so generating the fixture
/// never costs the memory the test is trying to measure.
enum SyntheticPayload {
    @discardableResult
    static func writeFormulae(to url: URL, targetBytes: Int) throws -> Int {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.write(contentsOf: Data("[".utf8))
        var written = 1
        var index = 0
        while written < targetBytes {
            let record = Data("\(index == 0 ? "" : ",")\(Self.record(index: index))".utf8)
            try handle.write(contentsOf: record)
            written += record.count
            index += 1
        }
        try handle.write(contentsOf: Data("]".utf8))
        return written + 1
    }

    /// ~6 kB per record, so 40 MB is ~7,100 records — the same order as the live
    /// dump's 31 MB / 8,529. Most of each record is padding under keys the wire
    /// types deliberately do not model, which is precisely the cost D8 claims
    /// the narrow schema avoids paying.
    private static func record(index: Int) -> String {
        let padding = String(repeating: "abcdefghij0123456789", count: 140)
        return """
        {"name":"pkg\(index)","full_name":"pkg\(index)","tap":"homebrew/core",\
        "desc":"Synthetic package number \(index) for the decode memory budget",\
        "license":"MIT","homepage":"https://example.invalid/pkg\(index)",\
        "versions":{"stable":"1.\(index % 100).0","head":"HEAD","bottle":true},\
        "dependencies":["pkg\(max(0, index - 1))","pkg\(max(0, index - 2))"],\
        "build_dependencies":["pkgconf"],"uses_from_macos":["curl",{"llvm":["build"]}],\
        "caveats":null,"deprecated":false,"disabled":false,\
        "unmodelled_bottle_blob":"\(padding)","unmodelled_urls":"\(padding)"}
        """
    }
}

/// `phys_footprint` — the number macOS actually charges the process, including
/// touched mapped pages and the malloc zones a `resident_size` reading misses.
enum MemoryProbe {
    static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Samples the footprint from a plain thread, because the work being
    /// measured is a synchronous CPU burst that would starve a cooperative pool.
    final class Sampler: Sendable {
        private struct State {
            var peak: UInt64 = 0
            var running = false
        }

        private let state: Mutex<State> = Mutex(State())

        func start() {
            state.withLock {
                $0.peak = MemoryProbe.physFootprint()
                $0.running = true
            }
            nonisolated(unsafe) let shared = self
            Thread.detachNewThread {
                while shared.state.withLock({ $0.running }) {
                    let sample = MemoryProbe.physFootprint()
                    shared.state.withLock { if sample > $0.peak { $0.peak = sample } }
                    usleep(2_000)
                }
            }
        }

        func stop() -> UInt64 {
            let sample = MemoryProbe.physFootprint()
            return state.withLock {
                $0.running = false
                if sample > $0.peak { $0.peak = sample }
                return $0.peak
            }
        }
    }
}
