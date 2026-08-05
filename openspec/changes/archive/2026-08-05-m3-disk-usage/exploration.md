# Exploration: M3-3 Disk Usage

As-of: 2026-08-04, current `main` at `65eaf16` after M3-2 merged. This is exploration only.

### Current State

#### Package and dependency graph

`Packages/CellarCore/Package.swift` uses Swift tools 6.0, macOS 26, Swift language mode 6, and
currently declares:

```text
CellarTestSupport  (no dependencies; test-only, not a product)
BrewProcess        (no dependencies)
Catalog            (no dependencies; deliberately brew-free)
BrewClient         -> BrewProcess, Catalog
Persistence        -> BrewClient
```

The exact recommended M3-3 direction is:

```text
DiskUsage          -> BrewProcess, Catalog
BrewClient         -> BrewProcess, Catalog, DiskUsage
Persistence        -> BrewClient
cellar app          -> BrewClient, BrewProcess, Catalog, DiskUsage, Persistence
DiskUsageTests     -> DiskUsage, CellarTestSupport
```

`DiskUsage` must never depend on `BrewClient`, `Persistence`, or the app. `BrewClient` may depend on
the pure `DiskUsage` capability to bridge its shipped mutation settlement/refresh-receipt machinery
to `DiskUsageStore`; this direction remains acyclic and keeps the engine independently testable.

#### Detection and roots

- `BrewInstallation` exposes a validated `executableURL`, `BrewPrefix`, and version.
- The shipped watcher derives the prefix as two parents above `<prefix>/bin/brew`, then watches
  `<prefix>/Cellar` and `<prefix>/Caskroom`.
- Standard prefixes are `/opt/homebrew` and `/usr/local`. A custom installation stores the configured
  executable path in `.custom(URL)` and the resolved executable in `executableURL`; there is no
  canonical `prefixURL` API today. M3-3 should add one authoritative root projection rather than
  repeat parent traversal.
- The cache is not under the prefix. The active machine reports
  `/Users/juancasanueva/Library/Caches/Homebrew` from `brew --cache`.
- Root construction should be a pure `HomebrewRoots` value passed to the scanner. It should use the
  validated installation for the prefix and the user-domain Homebrew cache location, with existence
  checked independently per root. Missing Caskroom or cache is an empty category, not total failure.

#### Existing watcher and invalidation behavior

- `FSEventsInstalledObserver` is a small CoreServices bridge. It ignores event paths and emits only
  invalidation signals; the callback runs on a private queue.
- One observer instance is single-consumer: a second `changes()` call stops and supersedes the first.
  It must not be handed independently to two coordinators.
- The current app creates one observer after detection and forwards its Cellar/Caskroom signals to
  `InstalledRefreshCoordinator.changeDetected()`.
- Cache is not watched today. The safe reuse is to generalize root construction while retaining one
  stream for Cellar/Caskroom that the app fans out to installed and disk-usage coordinators, plus a
  cache-only stream that invalidates disk usage only. Adding cache to the installed stream would
  cause needless `brew info --installed` refreshes.
- `InvalidationScope` currently declares installed inventory, services, and taps; bit `1 << 3` is
  reserved in a comment for disk usage. M3-3 must declare `.diskUsage`, add its refresh domain/gate,
  and extend package mutations and force-untap to include it. The existing comment incorrectly says
  the already-declared taps bit is still reserved and should be corrected when that file is changed.
- `MutationRefreshRegistry` and `MutationTerminalEvent` live in `BrewClient`. This is why the bridge
  coordinator belongs in `BrewClient` while the scanner, cache, models, and store belong in
  `DiskUsage`; reversing that edge would create the wrong dependency.

#### Existing store, concurrency, and UI patterns

- Core package targets use nonisolated defaults; the app target defaults to `MainActor`.
- Existing stores are explicitly `@MainActor @Observable`, retain last-good state, invalidate before
  refresh, and guard adoption against stale completions.
- CPU-heavy decode already uses `@concurrent`. Disk traversal must likewise have an explicit
  off-main boundary; a plain `Task` inherited from the app's main actor is insufficient evidence.
- `cellarApp` owns stores, gates, coordinators, and app-lifetime loops. `ContentView` routes an
  exhaustive `AppSection` through a three-column `NavigationSplitView`.
- M3-3 should add a `Cleanup` section now, containing disk figures only. Cleanup commands and dry-run
  reclaimable-byte claims remain M3-4. The Installed-list size column remains explicitly M5.

#### Filesystem accounting semantics

- Headline values should be allocated bytes, not logical bytes. Apple documents
  `totalFileAllocatedSizeKey` as total allocated bytes including file metadata; logical/display size
  is a separate observation (`totalFileSizeKey`). Logical bytes may be retained diagnostically but
  must not be the primary user figure.
- Enumerate metadata only. Do not open file contents.
- Do not follow symlinks or Finder aliases. Count the link itself, but never traverse from Caskroom
  into `/Applications` or from cache links into another tree.
- De-duplicate hard-linked entries by stable file identity within a root. Use stable traversal order
  so attribution remains deterministic. APFS clones can share extents while retaining distinct file
  identities; exact exclusive physical-block attribution is not available through these APIs, so the
  UI must call values “on disk,” not “reclaimable.” M3-4's brew dry run owns reclaimable bytes.
- Treat each immediate Cellar child as a formula and each next-level child as a version. Treat each
  immediate Caskroom child as a cask token and its next level as a version. Preserve path component
  text; do not parse versions semantically.
- `brew info --installed --json=v2` already decodes `linked_keg`, but `InstalledPackage` currently
  collapses nil to “newest keg is primary,” losing whether the formula is actually unlinked. Current
  Homebrew 6.0.15 rejects `brew list --unlinked`; do not invent that command. Retain the structured
  `linked_keg` optional in the installed projection and pass a small Sendable link-state value into
  DiskUsage without adding a DiskUsage-to-BrewClient dependency.
- A missing `linked_keg` means an installed formula is unlinked; non-linked version directories are
  candidates for old-version display, not a promise that Homebrew will reclaim them. Pinned state and
  Homebrew cleanup policy make “eligible/reclaimable” a later dry-run decision.
- Permission failures, disappearing files, and concurrent renames must be recorded as partial errors,
  never silently converted to zero. Cancellation must not replace the last complete cache.

#### U7 traversal-cost probe

Measurement and design inference are intentionally separated below.

**Resolution command shape (executed read-only, 8-second timeout per command):**

```sh
brew_bin="${commands[brew]:-}"; if [[ -z "$brew_bin" ]]; then print -r -- \
  '{"error":"brew-not-found"}'; exit 1; fi; \
/usr/bin/ruby -rjson -ropen3 -rtimeout -e '
brew = ARGV.fetch(0); result = {brew: brew};
[["prefix", "--prefix"], ["cache", "--cache"], ["version", "--version"]].each do |key, flag|;
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC);
  begin;
    out, err, status = Timeout.timeout(8) { Open3.capture3(brew, flag) };
    result[key] = {
      value: out.lines.first&.strip, status: status.exitstatus, stderr: err.strip,
      elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(6),
      timed_out: false
    };
  rescue Timeout::Error;
    result[key] = {
      elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(6),
      timed_out: true
    };
  end;
end;
puts JSON.generate(result)' "$brew_bin"
```

Result: executable `/opt/homebrew/bin/brew`; prefix `/opt/homebrew` in 0.010119 s; cache
`/Users/juancasanueva/Library/Caches/Homebrew` in 0.008509 s; Homebrew
`6.0.15-42-ge5ed163` in 0.032193 s. All exited 0 with no stderr or timeout.

**Traversal command shape (executed once, metadata-only, 30-second timeout per root):**

```sh
/usr/bin/ruby -rjson -rset -rtimeout -e '
roots = [["cellar", ARGV[0]], ["caskroom", ARGV[1]], ["cache", ARGV[2]]];
deadline = 30;
results = roots.map do |label, root|;
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC);
  r = {
    label: label, root: root, exists: File.exist?(root) || File.symlink?(root),
    timeout_seconds: deadline, timed_out: false, entries: 0, unique_inodes: 0,
    duplicate_inode_entries: 0, directories: 0, regular_files: 0, symlinks: 0,
    other_entries: 0, allocated_bytes: 0, logical_bytes: 0, errors: {}
  };
  if r[:exists];
    seen = Set.new; stack = [root];
    begin;
      Timeout.timeout(deadline) do;
        until stack.empty?;
          path = stack.pop;
          begin;
            stat = File.lstat(path); r[:entries] += 1;
            if stat.directory?;
              r[:directories] += 1;
              begin;
                Dir.each_child(path) { |name| stack << File.join(path, name) };
              rescue SystemCallError => e;
                key = e.class.name; r[:errors][key] = r[:errors].fetch(key, 0) + 1;
              end;
            elsif stat.file?; r[:regular_files] += 1;
            elsif stat.symlink?; r[:symlinks] += 1;
            else; r[:other_entries] += 1;
            end;
            inode = [stat.dev, stat.ino];
            if seen.add?(inode);
              r[:allocated_bytes] += stat.blocks * 512; r[:logical_bytes] += stat.size;
            else; r[:duplicate_inode_entries] += 1;
            end;
          rescue SystemCallError => e;
            key = e.class.name; r[:errors][key] = r[:errors].fetch(key, 0) + 1;
          end;
        end;
      end;
    rescue Timeout::Error; r[:timed_out] = true;
    end;
    r[:unique_inodes] = seen.size;
  end;
  r[:elapsed_seconds] =
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(6);
  r[:error_state] = r[:timed_out] ? "timeout" : (r[:errors].empty? ? "none" : "partial");
  r;
end;
complete = results.reject { |r| !r[:exists] || r[:timed_out] };
totals = {
  existing_roots: results.count { |r| r[:exists] }, completed_roots: complete.length,
  timed_out_roots: results.count { |r| r[:timed_out] },
  entries: complete.sum { |r| r[:entries] },
  unique_inodes: complete.sum { |r| r[:unique_inodes] },
  allocated_bytes: complete.sum { |r| r[:allocated_bytes] },
  logical_bytes: complete.sum { |r| r[:logical_bytes] },
  elapsed_seconds_sum: results.sum { |r| r[:elapsed_seconds] }.round(6)
};
puts JSON.pretty_generate({
  semantics: {
    walk: "iterative Dir.each_child plus File.lstat", follows_symlinks: false,
    hard_link_bytes: "counted once per device/inode within each root",
    allocated: "st_blocks * 512", logical: "st_size", reads_file_contents: false
  }, roots: results, totals: totals
})
' "/opt/homebrew/Cellar" "/opt/homebrew/Caskroom" \
  "/Users/juancasanueva/Library/Caches/Homebrew"
```

No repository scratch file was created, no file content was opened, no Homebrew mutation or lock was
requested, and timeout interrupts return a partial result marked `timeout` rather than hanging.

| Root | Exists | Entries | Unique inodes | Allocated bytes | Logical bytes | Elapsed | Timeout/error |
|---|---:|---:|---:|---:|---:|---:|---|
| `/opt/homebrew/Cellar` | yes | 120,541 | 120,533 | 4,185,178,112 | 3,902,351,957 | 2.461066 s | none |
| `/opt/homebrew/Caskroom` | yes | 123 | 123 | 69,632 | 37,223 | 0.004042 s | none |
| `~/Library/Caches/Homebrew` | yes | 3,302 | 3,302 | 2,475,282,432 | 2,469,593,386 | 0.083255 s | none |
| **Completed totals** | **3/3** | **123,966** | **123,958** | **6,660,530,176** | **6,371,982,566** | **2.548363 s** | **0 timeouts** |

The eight duplicate inode entries occurred in Cellar. Caskroom's tiny result is consistent with its
84 symlinks not being followed; it does not claim the size of linked applications outside Caskroom.

**Design inference from the measurements:** Cellar alone takes about 2.46 seconds on this machine,
so a launch/view-appearance full walk is visibly expensive. Persisted stale-while-revalidate cache,
package/version-boundary incremental publication, explicit cancellation, and FSEvents invalidation
are requirements, not optional optimizations. The data does not justify parallel subtree walks;
concurrent metadata storms may worsen latency and make deterministic attribution harder.

### Affected Areas

- `Packages/CellarCore/Package.swift` — add product/target/test target and the one-way BrewClient edge.
- `Packages/CellarCore/Sources/DiskUsage/` — roots, accounting models, scanner, cache, store, and
  incremental events.
- `Packages/CellarCore/Tests/DiskUsageTests/` — fake-driven behavior tests and bounded temp-tree
  integration fixtures.
- `Packages/CellarCore/Sources/BrewClient/BrewMutating.swift` — `.diskUsage` scope/domain mapping;
  package and force-untap invalidation.
- `Packages/CellarCore/Sources/BrewClient/InstalledModels.swift` and `InstalledDecoder.swift` — retain
  exact optional `linked_keg` state instead of losing “unlinked.”
- `Packages/CellarCore/Sources/BrewClient/FSEventsInstalledObserver.swift` — reusable explicit-root
  construction without adding cache changes to installed refreshes.
- `Packages/CellarCore/Sources/BrewClient/` — disk refresh bridge for mutation receipts, suppression,
  and terminal settlement.
- `cellar/cellarApp.swift` — own/inject store and coordinator, register the disk gate, fan out shared
  Cellar/Caskroom events, and run cache-only observation.
- `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`, `cellar/Cleanup/` — Cleanup route and
  sortable incremental list surface.
- `cellar.xcodeproj/project.pbxproj` — link the new local-package product and add app files.
- `Packages/CellarCore/Tests/CatalogTests/PackageGraphTests.swift` — enforce the new dependency
  direction and forbidden reverse edges.

### Approaches

1. **Native metadata scanner with incremental events and persisted cache** — a `DiskUsage` target
   enumerates metadata with a focused `DirectoryMeasuring` seam, publishes completed package/version
   units, and atomically persists only complete snapshots.
   - Pros: fine-grained cancellation and progress; deterministic error handling; direct testing with
     a fake and temp trees; no subprocess parsing; fits Swift 6 Sendable boundaries.
   - Cons: must define hard-link, symlink, APFS-clone, race, and cache semantics explicitly; largest
     authored/test surface.
   - Effort: High.

2. **Bounded `/usr/bin/du` subprocesses per root/subtree** — run `du` for each category or package and
   parse byte totals.
   - Pros: compact initial implementation; mature filesystem traversal; process cancellation can be
     bounded.
   - Cons: many package/version processes or no useful incremental progress; output parsing and
     locale/flag semantics; weak per-entry error reporting; hard to share one traversal across totals;
     adds another process lifecycle outside the brew runner without reducing cache/UI work.
   - Effort: Medium initially, High once incremental per-package behavior is included.

### Recommendation

Choose approach 1. Use a small Sendable event model (`started`, package/version result, category
result, partial warning, completed), with a production `DirectoryMeasuring` implementation and a
scriptable fake. Run production traversal on an explicit concurrent executor, check cancellation at
every entry and unit boundary, and let the main-actor `DiskUsageStore` own one generation/task so late
results cannot overwrite newer state.

Persist the last complete snapshot atomically, keyed by resolved roots and an accounting-schema
version. Publish it immediately as stale, then revalidate. FSEvents and relevant mutation terminals
mark it stale; they do not erase last-good data. Never persist a cancelled or partial generation.

Publish at package/version boundaries, not per inode. The U7 machine has roughly 156 formulae but
120,541 Cellar entries, so this provides useful progress without tens of thousands of main-actor
updates. Sorting should be a pure projection over stable row IDs with deterministic tie-breakers;
selection remains identity-based while rows arrive. The Cleanup surface should show allocated size,
kind, versions, linked/unlinked state, and errors, with sort by size/name/kind. It must not add a size
column to Installed.

Testing should combine fake-driven store/cancellation/cache tests with deterministic temporary trees.
Temp fixtures must include nested package/version directories, missing roots, unreadable/disappearing
entries where safely simulatable, symlink loops/out-of-root links, hard links, and cancellation. Do not
assert fixed APFS allocated block counts; compare against resource values observed from the fixture or
assert invariants. Use Swift Testing time limits and confirmations/gates, never sleeps.

The previous 2,800–3,800 authored-line forecast remains credible and may move toward 3,000–4,200
because U7 makes persisted cache mandatory and the shipped refresh-receipt system now needs a fourth
domain. This exceeds the 2,000-line single-PR review budget. The proposal round must obtain an explicit
`size:exception` or reduce/split scope; apply remains blocked until that decision.

### Risks

- Traversal is already multi-second on the development machine; unbounded refreshes will visibly
  regress the app.
- Cache invalidation can be too broad (needless scans) or too narrow (stale figures), especially for
  cache changes and CLI-side mutations while Cellar is closed.
- Files may disappear, permissions may change, and external brew operations may race traversal.
- APFS clones and hard links prevent a perfect per-package claim of exclusive physical bytes.
- Following Caskroom/cache symlinks would count bytes outside Homebrew's managed roots.
- The existing installed projection loses exact unlinked state even though the wire payload carries it.
- The FSEvents adapter is single-consumer; naïve reuse would silently stop the installed watcher.
- A new product, new target, app route, persisted cache, fourth invalidation domain, fixtures, and UI
  make the 2,000-line reviewer burden high.

### Ready for Proposal

Yes. U7 is closed with bounded current-machine evidence, the dependency direction and watcher reuse
constraint are known, and there is a recommended implementation approach. Native lifecycle should
register the named change with `sdd-new`, then run the interactive proposal-question round. That round
must settle the single-PR `size:exception`; no apply work is authorized.
