# PRD — Cellar! (working title)

**A native Homebrew GUI for macOS** — SwiftUI, no backend, free. No tip jar (see §6).

| | |
|---|---|
| **Platform** | macOS 26 Tahoe+, Apple Silicon only (arm64) |
| **Stack** | Swift 6.x, SwiftUI (Liquid Glass design system), SwiftData, local SPM core package (`CellarCore`) |
| **Distribution** | Direct download (Developer ID + notarized, Sparkle updates) **and** Homebrew cask |
| **Monetization** | Free, ad-free, no tip jar (decision at M6 — §6) |
| **Backend** | None. Talks only to the local `brew` binary, formulae.brew.sh, GitHub API, and OSV/NVD CVE feeds |
| **Reference product** | TapHouse 1.5 (feature parity target, brew-only scope) |

---

## 1. Overview

Cellar! is a full-featured visual layer over the `brew` binary already installed on the user's Mac. It surfaces everything that is tedious from the command line — searching 14,000+ formulae and casks, outdated packages, per-package disk usage, service status, dependency trees, CVE exposure — and executes the same `brew` commands the user would type, with real-time progress and logs.

**Product principles**

1. **Native or nothing.** Pure SwiftUI, feels like part of macOS. No web views, no Electron.
2. **brew is the source of truth.** Cellar! never manipulates the Cellar/Caskroom directly for mutations; it always shells out to `brew`. The CLI and the GUI can coexist mid-task.
3. **Local-first, private.** No accounts, no telemetry, no backend. Network calls limited to package metadata, release notes, and CVE feeds.
4. **Free forever.** All features free (including everything TapHouse gates behind Pro). No tip jar — a StoreKit one was built and removed at M6 (§6).

**Non-goals (v1)**

- Third-party (non-brew) app updates (Sparkle/GitHub-distributed apps) — deferred
- Mac App Store update integration — deferred
- Installing Homebrew itself (detect-and-guide only; link to brew.sh)
- MacPorts / other package managers
- iOS/iPadOS anything

---

## 2. Target users

- **Developers** who live in brew but want batch updates, service dashboards, and CVE visibility without ritual incantations.
- **Power users / switchers** who installed brew from a tutorial and are uncomfortable maintaining it from Terminal.
- **Security-conscious users** who want to know which installed packages have published CVEs.

---

## 3. Feature specification

Features are grouped into the seven main navigation areas plus cross-cutting capabilities. Everything below is **free** in Cellar!.

### 3.1 Browse (package catalog)

- Search across all formulae and casks from the Homebrew JSON API (formulae.brew.sh), cached locally and refreshed in the background (default: every 24h, manual refresh available).
- Instant, as-you-type local search (name, description, token); filters: formula/cask, installed/not installed, outdated, deprecated/disabled.
- Package detail view: description, homepage, license, current version, dependencies (build/runtime, recursive tree view), dependents ("required by"), analytics (365-day install count), caveats, deprecation/disabled status, tap of origin.
- **Pre-install cask inspection**: for casks, show the artifact list (what gets installed where), download URL, whether the app is signed/notarized (checked post-download during install via `codesign`/`spctl` on the staged artifact when feasible; otherwise surfaced after install), and auto-updates flag.
- **Discover tab**: curated/featured sections — most-installed formulae and casks (from Homebrew analytics API), "new to you" (packages that appeared since your last catalog sync — formulae.brew.sh publishes no date-added data, so newness is derived locally from successive catalog snapshots; empty on first run), and a hand-curated JSON list shipped with the app (updatable via app releases).

### 3.2 Installed

- Unified list of installed formulae + casks with: version(s), installed-on-request vs dependency, outdated badge, pinned badge, size on disk, last used (formulae: mtime heuristics on linked binaries; casks: app bundle `kMDItemLastUsedDate` via Spotlight metadata).
- **One-click install / uninstall / reinstall** with live streamed logs (stdout+stderr), progress states, cancel support, and a persistent activity log.
- **Bulk operations**: multi-select → upgrade, uninstall, pin, snooze.
- **Upgrade flows**: upgrade single, upgrade selected, upgrade all. Casks with `auto_updates: true` are visually separated (updating them via brew is usually unnecessary).
- **Pinning** (`brew pin`/`unpin`) surfaced as a toggle; **favorites** and **per-package notes** (local metadata, SwiftData).
- **Snooze updates**: hide a package's outdated badge for 1 day / 1 week / 1 month / until next version. Snoozes stored locally with the version they apply to.
- **Release notes preview**: before upgrading, fetch the changelog from GitHub Releases (resolved from the formula/cask homepage or `stable` URL when it points at GitHub). Rendered as Markdown in a sheet. Graceful "no release notes found" fallback.
- **Installation history**: local log of every install/uninstall/upgrade performed through the app (date, package, version from→to, outcome), searchable.

### 3.3 Services

- List `brew services` output with color-coded status (started/stopped/error), user vs root domain, and the underlying formula.
- Start / stop / restart / run-once per service; "start at login" toggle (`brew services start` vs `run`).
- View service log file paths and open them in Console.app; show the plist location.
- Auto-refresh while the Services view is visible.

### 3.4 Health (dashboard)

At-a-glance snapshot combining:

- Outdated packages count (formulae/casks split)
- Vulnerable packages count (from CVE scanner)
- Orphaned dependencies (installed as dependency, no longer required by anything — `brew autoremove --dry-run`)
- Duplicate old versions in the Cellar
- Cache size (`~/Library/Caches/Homebrew`)
- Last `brew update` time; `brew doctor` summary (warnings parsed and grouped, full output viewable)
- A composite **health score** (0–100) with a transparent breakdown of how it is computed
- One-click remediation per row (upgrade all, autoremove, cleanup, run doctor)

### 3.5 Security

- **CVE scanner**: cross-reference every installed formula+version against vulnerability data.
  - Primary source: OSV.dev batch query API (free, no key, supports querying by package/version); NVD 2.0 API as enrichment/fallback for CVSS scores where OSV lacks severity.
  - Severity tiers (low/medium/high/critical), color-coded; links to NVD and vendor advisories.
  - "Fixed in" version detection → **one-click upgrade** for vulnerabilities resolved by a newer bottled version.
  - Background re-scan on schedule (default daily) and after any install/upgrade; results cached with scan timestamp.
  - Honest UX: clearly label matches as "reported for this package/version" — name-based matching can produce false positives; provide a per-CVE "dismiss / not applicable" action (persisted).
- **Security insights** per cask app: code-signing identity, notarization status (`codesign -dv`, `spctl -a`), Gatekeeper quarantine flag.
- **Quarantine manager**: list apps/files under brew-managed locations (and `/Applications` apps installed via casks) carrying `com.apple.quarantine`; review and clear flags individually or in bulk (direct `removexattr`, no shell `xattr` dependency). Confirmation dialog with a plain-language explanation of what clearing quarantine means.

### 3.6 Cleanup & disk usage

- Visual breakdown of what brew is consuming: Cellar (per-package, per-version), Caskroom, download cache, old versions eligible for cleanup, orphaned dependencies, unlinked kegs.
- Sizes computed off the main thread with incremental display; sortable treemap-or-list (list in v1, treemap stretch).
- Actions: `brew cleanup` (all or per-package), `brew cleanup --prune=all`, `brew autoremove`, purge download cache. Every destructive action shows a dry-run preview (`--dry-run`/`-n` parsed) with reclaimable bytes before confirmation.
- Duplicate & orphan detection surfaced here and on the Health dashboard.

### 3.7 Taps & Brewfile

- **Taps manager**: list taps, add (`brew tap user/repo`), remove, show packages per tap. Warning copy when adding third-party taps (untrusted code).
- **Brewfile import/export**: generate a Brewfile from current state (`brew bundle dump` semantics — taps, formulae, casks; MAS entries excluded in v1), export to file/share sheet; import a Brewfile with a diff preview (what would be installed/missing) and selective apply via `brew bundle --file`.

### 3.8 Menu bar & background

- Optional **menu bar extra** (MenuBarExtra): outdated count badge, top outdated packages, quick "upgrade all", quick service toggles, open main window.
- **Background update checks** via login item (SMAppService) + periodic `brew update` and outdated/CVE re-scan on a user-configurable schedule (off by default; options 6h/12h/daily/weekly).
- User notifications (UNUserNotificationCenter): "N packages outdated", "New CVE affects <pkg>", operation-finished notifications for long installs. All individually toggleable.

### 3.9 Cross-cutting

- **Command transparency**: every mutation shows the exact `brew` command being run; a global Activity view streams logs of current and past operations. "Copy command" everywhere.
- **Operation queue**: brew locks preclude parallel mutations — Cellar! serializes all mutating operations through a queue with visible pending items; read-only queries run concurrently.
- **brew detection & onboarding**: on first launch detect brew at `/opt/homebrew/bin/brew` (native), `/usr/local/bin/brew` (an x86_64 install carried over via Migration Assistant/Rosetta — supported, but flagged with a suggestion to migrate to the native prefix), or custom path (validated). If absent: friendly guide linking to brew.sh with the install one-liner (copy button) — Cellar! does not install Homebrew itself in v1.
- **Localization**: English + Spanish at launch (String Catalogs).
- **Accessibility**: full keyboard navigation, VoiceOver labels on all controls, Dynamic Type where applicable, respects Reduce Motion.
- **Settings**: brew path, refresh/scan schedules, notifications, menu bar toggle, appearance, Sparkle update channel. (A tip-jar card lived here briefly at M6; removed — §6.)

---

## 4. Architecture

### 4.1 Shape

Same pattern as Fuse!/Shelf!: thin SwiftUI app target + a local SPM package holding all logic, protocol-first and fully testable without a GUI.

```
Cellar.xcodeproj
├── Cellar (app target)          # SwiftUI views, scenes, MenuBarExtra, DI wiring
└── Packages/CellarCore (SPM)
    ├── BrewProcess              # Process execution, streaming, cancellation, queue
    ├── BrewClient               # Typed commands: install, uninstall, upgrade, pin,
    │                            #   services, cleanup, tap, bundle, doctor, outdated
    ├── Catalog                  # formulae.brew.sh sync, local search index, analytics
    ├── SecurityKit              # OSV/NVD clients, CVE matching, codesign/spctl,
    │                            #   quarantine xattr handling
    ├── DiskUsage                # Cellar/Caskroom/cache sizing, dry-run parsing
    ├── ReleaseNotes             # GitHub Releases resolution + fetching
    └── Persistence              # SwiftData models + migrations
```

### 4.2 Key decisions

- **Executing brew.** `Foundation.Process` wrapped in an `actor BrewRunner`. Environment: `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_INSTALL_FROM_API` unset (default API mode), `HOMEBREW_COLOR=0`, `HOMEBREW_NO_EMOJI=1` for parseable output. `--json=v2` wherever supported (`info`, `outdated`, `services list --json`). Streaming via `FileHandle.readabilityHandler` → `AsyncStream<LogLine>`. One mutating operation at a time (queue); reads concurrent. Cancellation = SIGINT then SIGTERM escalation.
- **Never run as root.** Services in the root domain that require sudo are shown read-only with an explainer; no privilege escalation in v1.
- **Catalog data.** `formula.json` + `cask.json` from formulae.brew.sh (~25 MB combined) downloaded to Application Support, decoded off-main, indexed into an in-memory search structure (token + name trigram). Analytics from the analytics API endpoints. ETag/If-Modified-Since to avoid re-downloads.
- **Installed state.** `brew info --installed --json=v2` as the authoritative snapshot; refreshed after every mutation and on window focus (debounced). File-system watcher (DispatchSource) on the Cellar/Caskroom to catch CLI-side changes while the app is open.
- **CVE matching.** OSV batch endpoint with `{package name, version}`; enrich with NVD CVSS where missing. Cache per (name, version) with TTL. All matching logic pure + unit-tested against fixture responses.
- **Persistence (SwiftData).** Models: `PackageMeta` (favorites, notes), `Snooze`, `HistoryEntry`, `DismissedCVE`, `Settings`. No CloudKit in v1 (data is machine-specific).
- **Sandbox: off.** Hardened runtime on, sandbox off (required to exec brew). Entitlements kept minimal; document why in-repo for notarization sanity.
- **Concurrency.** Swift 6 language mode with strict concurrency; `@Observable` view models; all Process and disk-size work off the main actor. macOS 26 minimum means the latest SwiftUI/SwiftData APIs can be used unconditionally — no `#available` branches anywhere.

### 4.3 External services (all optional to core operation)

| Service | Purpose | Auth |
|---|---|---|
| formulae.brew.sh | Catalog + analytics | none |
| api.osv.dev | CVE data (primary) | none |
| services.nvd.nist.gov | CVSS enrichment, advisory links | none (rate-limited; API key optional in Settings) |
| api.github.com | Release notes | none (60 req/h unauthenticated; optional PAT in Settings) |
| Cellar! update feed | Sparkle appcast (static XML on GitHub Pages/Releases) | none |

Failure of any external service degrades gracefully (feature shows cached/empty state; core brew operations unaffected).

---

## 5. UI/UX

- **Navigation**: `NavigationSplitView` — sidebar (Discover, Browse, Installed, Outdated, Services, Health, Security, Cleanup, Taps, History) → list → detail. Toolbar search scoped per section. ⌘K quick-open for any package.
- **Design language**: macOS 26 Liquid Glass throughout — standard glass toolbars/sidebars, `.glassEffect` only where system components don't provide it, no custom chrome. SF Symbols, accent-colored status chips (green running / orange outdated / red vulnerable), monospaced log views. Light/dark. Targeting 26+ exclusively means no availability checks or dual design paths.
- **Long operations**: bottom activity bar with progress + expandable log drawer; operations survive view navigation; app quit with active operations prompts (operation continues in brew if user force-quits — warn accordingly).
- **Destructive actions**: uninstall/cleanup/quarantine-clear always show scope + reclaimed bytes + exact command; require confirmation; no "don't ask again" for uninstalls.
- **Empty/error states**: every section designed for brew-missing, offline, and zero-results states.

---

## 6. Monetization & distribution

- **Tip jar — removed (M6 final decision).** The history, kept because each step was reasoned: this line originally chose external links (GitHub Sponsors / Ko-fi / Stripe) because StoreKit is unavailable outside the App Store — which is true. At M6 a $0.99 StoreKit consumable was built, verified and merged (PR #55) under a Mac App Store pivot. The U22 feasibility spike then *measured* what the original reasoning assumed: MAS is infeasible for Cellar — the App Sandbox denies `file-read-data` on `/opt/homebrew` before brew can exec (kernel-level, not reviewable), Guidelines 2.5.2/2.4.5 forbid installing executable code, and no Homebrew GUI exists on MAS. Offered the external-links fallback, the maintainer chose **no tip jar at all**: Cellar is free, with no payment surface of any kind. The StoreKit implementation was reverted in the same decision; its SDD archive (with the U22 report) remains at `openspec/changes/archive/2026-08-22-m6-tip-jar/`.
- **Signing**: Developer ID Application cert, hardened runtime, notarization via `notarytool` in CI (GitHub Actions on tags).
- **Sparkle 2**: EdDSA-signed appcast hosted on GitHub Pages; delta updates later. In-app "Check for updates".
- **Cask channel**: submit to homebrew-cask once the app meets notability requirements (GitHub stars/press); until then, self-hosted tap `juan/tap` so `brew install --cask cellar` works day one. Sparkle auto-update disabled-by-prompt when installed via cask? No — casks and Sparkle coexist fine; mark cask `auto_updates true` so `brew upgrade` skips it by default.
- **Website**: single static landing page (download, screenshots, privacy). No analytics beyond server logs.

---

## 7. Milestones

**M1 — Core & Catalog (foundation)**
CellarCore package scaffolding; BrewRunner actor with streaming + tests; brew detection/onboarding; catalog sync + local search; Browse UI with package detail (info, deps, analytics). *Exit: search 14k packages instantly, view any package's full details.*

**M2 — Mutations & Installed**
Install/uninstall/reinstall with live logs, cancel, operation queue; Installed list with outdated detection; upgrade single/selected/all; pin, favorites, notes, snooze; installation history. *Exit: full daily package management without Terminal.*

**M3 — Services, Cleanup & Taps**
Services view with start/stop/restart; disk usage engine + Cleanup view with dry-run previews; autoremove/orphans; taps manager. *Exit: TapHouse free-tier parity minus security.*

**M4 — Security**
OSV/NVD clients + CVE matching engine (fixture-tested); Security view with severity tiers, fix-version upgrades, dismissals; codesign/notarization insights; quarantine manager. *Exit: the headline differentiator works end-to-end.*

**M5 — Pro-parity flows**
Health dashboard + score; pre-install cask inspection; release notes preview; Brewfile import/export; bulk operations polish; Discover tab. *Exit: full TapHouse feature parity (brew-only scope).*

**M6 — Ship**
Menu bar extra; background checks + notifications (SMAppService); Settings; Spanish localization; accessibility pass; Sparkle integration; CI signing/notarization pipeline; self-hosted tap; landing page. (Tip jar was M6's first slice — built, then removed by decision; §6.) *Exit: 1.0 public release.*

---

## 8. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| brew output/JSON schema changes across versions | Parsers break | Pin minimum supported brew version (4.x); tolerant decoding; integration tests run against real brew in CI (macOS runner) |
| CVE false positives (name-based matching) | User distrust | Conservative matching, explicit "reported for" language, per-CVE dismiss, link to source |
| Long `brew upgrade` runs blocking UX expectations | Perceived hangs | Streaming logs, cancel, queue visibility, notifications on completion |
| NVD/GitHub rate limits | Missing enrichment | Aggressive caching, optional user API keys, OSV as primary |
| Notarization + no-sandbox friction | Release delays | Set up CI pipeline in M1, not M6; test notarized builds early |
| Cask notability rejection | Discoverability | Self-hosted tap from day one; pursue main tap post-traction |
| TapHouse similarity | Perception | Clone features, not assets/copy/name; original icon, UI layout, and text throughout |
| macOS 26+ / arm64-only floor excludes Sonoma–Sequoia and all Intel users (TapHouse supports 14+ Universal) | Smaller addressable market at launch | Accepted trade-off for a single modern codebase and simpler CI; brew users skew current hardware; Tahoe's Intel base is ~4 legacy models anyway |

---

## 9. Open questions

1. Final name + icon direction (Cellar! proposed; verify no trademark/App-name conflicts at registration time).
2. ~~Tip jar provider~~ — **resolved at M6: none.** StoreKit was built then removed after the U22 spike measured MAS infeasible, and the maintainer declined external links (§6).
3. Whether M4's CVE scanner should also cover casks (OSV coverage for GUI apps is sparse — likely formulae-only in v1, casks later).
4. Treemap visualization for disk usage — v1 stretch or v1.1.
5. `brew doctor` parsing depth: raw output vs structured grouping (start raw, iterate).
