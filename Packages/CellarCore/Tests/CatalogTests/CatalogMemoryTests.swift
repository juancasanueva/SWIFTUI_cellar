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

    @Test(
        "Decoding a 40 MB payload stays inside the peak and retained budgets",
        .timeLimit(.minutes(2)),
        // Process footprint is only the decoder's while nothing else in the
        // process is holding a catalog-sized fixture.
        .heavyFixture
    )
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

/// Writes a realistic dump straight to disk, so generating the fixture never
/// costs the memory the test is trying to measure.
///
/// Two axes: `targetBytes` (the decode budget's question — how big a payload)
/// and `count` + `widened` (the footprint budget's question — how many records,
/// and whether they carry the M5 inspection keys). The unwidened content of a
/// widened record is byte-identical to its baseline twin, so a baseline-versus-
/// widened comparison measures the widening and nothing else.
enum SyntheticPayload {
    @discardableResult
    static func writeFormulae(to url: URL, targetBytes: Int) throws -> Int {
        try write(to: url) { index, written in
            written < targetBytes ? record(index: index, widened: false) : nil
        }
    }

    @discardableResult
    static func writeFormulae(to url: URL, count: Int, widened: Bool) throws -> Int {
        try write(to: url) { index, _ in
            index < count ? record(index: index, widened: widened) : nil
        }
    }

    @discardableResult
    static func writeCasks(to url: URL, count: Int, widened: Bool) throws -> Int {
        try write(to: url) { index, _ in
            index < count ? caskRecord(index: index, widened: widened) : nil
        }
    }

    /// Streams records into a JSON array, asking `next` for one at a time.
    private static func write(
        to url: URL,
        next: (_ index: Int, _ written: Int) -> String?
    ) throws -> Int {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.write(contentsOf: Data("[".utf8))
        var written = 1
        var index = 0
        while let record = next(index, written) {
            let data = Data("\(index == 0 ? "" : ",")\(record)".utf8)
            try handle.write(contentsOf: data)
            written += data.count
            index += 1
        }
        try handle.write(contentsOf: Data("]".utf8))
        return written + 1
    }

    /// ~6 kB per record, so 40 MB is ~7,100 records — the same order as the live
    /// dump's 31 MB / 8,529. Most of each record is padding under keys the wire
    /// types deliberately do not model, which is precisely the cost D8 claims
    /// the narrow schema avoids paying.
    private static func record(index: Int, widened: Bool) -> String {
        let padding = String(repeating: "abcdefghij0123456789", count: 140)
        let urls = widened ? """
        "urls":{"stable":{"url":"https://example.invalid/releases/pkg\(index)-1.\(index % 100).0.tar.gz",\
        "tag":null,"revision":null,"checksum":"\(digest(index: index))"},\
        "head":{"url":"https://github.invalid/example/pkg\(index).git","branch":"main"}},
        """ : ""
        return """
        {"name":"pkg\(index)","full_name":"pkg\(index)","tap":"homebrew/core",\
        "desc":"Synthetic package number \(index) for the decode memory budget",\
        "license":"MIT","homepage":"https://example.invalid/pkg\(index)",\
        "versions":{"stable":"1.\(index % 100).0","head":"HEAD","bottle":true},\
        \(urls)\
        "dependencies":["pkg\(max(0, index - 1))","pkg\(max(0, index - 2))"],\
        "build_dependencies":["pkgconf"],"uses_from_macos":["curl",{"llvm":["build"]}],\
        "caveats":null,"deprecated":false,"disabled":false,\
        "unmodelled_bottle_blob":"\(padding)","unmodelled_urls":"\(padding)"}
        """
    }

    /// Shaped after `Fixtures/cask-iterm2.json`, which is a verbatim live
    /// record: one `app` stanza with a destination, a `zap` stanza of the size
    /// real casks publish, a macOS bound and a conflict. `CatalogFootprintTests`
    /// anchors the encoded size of these against that fixture, so a change here
    /// that makes them thinner fails a test rather than quietly loosening a bound.
    private static func caskRecord(index: Int, widened: Bool) -> String {
        let padding = String(repeating: "abcdefghij0123456789", count: 90)
        // A quarter of real casks publish caveats, and the modelled fields of a
        // real record are considerably wordier than a `pkg123` placeholder. Both
        // matter: the bound is a ratio, so a thin baseline inflates it. The
        // anchor in `CatalogFootprintTests` is what holds this honest.
        let caveats = index % 4 == 0
            ? "\"caveats\":\"Cask \(index) is not signed by its publisher's usual identity, and macOS will ask you to confirm the first launch from the Finder rather than from Launchpad.\","
            : "\"caveats\":null,"
        let inspection = widened ? """
        "url":"https://downloads.example.invalid/cask\(index)/Cask\(index)-2.\(index % 100).0.dmg",\
        "sha256":"\(digest(index: index))",\
        "artifacts":[{"app":["Cask \(index).app"],"target":"/Applications/Cask \(index).app"},\
        {"zap":[{"trash":["~/Library/Application Support/Cask\(index)",\
        "~/Library/Caches/invalid.example.cask\(index)",\
        "~/Library/Preferences/invalid.example.cask\(index).plist",\
        "~/Library/Saved Application State/invalid.example.cask\(index).savedState"]}]},\
        {"uninstall":[{"quit":"invalid.example.cask\(index)"}]}],\
        "depends_on":{"macos":{">=":["13"]}},\
        "conflicts_with":{"cask":["cask\(index)@beta"]},
        """ : ""
        return """
        {"token":"cask\(index)","full_token":"cask\(index)","tap":"homebrew/cask",\
        "name":["Cask \(index) Professional Edition","Cask \(index)"],\
        "desc":"Synthetic cask number \(index) standing in for a published record \
        in the catalog footprint budget",\
        "homepage":"https://www.example.invalid/products/cask\(index)/download",\
        "version":"2.\(index % 100).0-build.\(index)",\
        \(inspection)\
        \(caveats)"auto_updates":false,"deprecated":false,"disabled":false,\
        "unmodelled_variations":"\(padding)","unmodelled_ruby_source":"\(padding)"}
        """
    }

    /// A deterministic 64-character hex string, the shape a real `sha256` is.
    private static func digest(index: Int) -> String {
        let seed = String(format: "%08x", index &* 2_654_435_761 & 0xFFFF_FFFF)
        return String(String(repeating: seed, count: 8).prefix(64))
    }
}

/// Malloc-zone bytes currently in use across every zone in the process.
///
/// The counterpart to `MemoryProbe.physFootprint()`, and used instead of it
/// wherever two shapes are compared **inside one process**. `phys_footprint`
/// never falls when magazine malloc frees, so the second measurement in such a
/// pair reads the first one's high-water mark and the comparison proves nothing.
/// This figure does fall, which is exactly the property a before/after delta
/// needs (probe U4's recorded measurement gotcha).
enum MallocProbe {
    static func bytesInUse() -> Int {
        Int(mstats().bytes_used)
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
    struct SamplerState {
        var peak: UInt64 = 0
        var running = false
    }

    final class Sampler: Sendable {
        private let state: Mutex<SamplerState> = Mutex(SamplerState())

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
