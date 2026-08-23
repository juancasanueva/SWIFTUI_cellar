# Cellar

**A native Homebrew GUI for macOS.** Pure SwiftUI, no backend, free.

Cellar is a full-featured visual layer over the `brew` binary already on your Mac. It surfaces everything that is tedious from the command line — searching 14,000+ formulae and casks, pending updates, per-package disk usage, service status, dependency trees, CVE exposure — and executes the same `brew` commands you would type, with real-time progress and logs.

## Principles

1. **Native or nothing.** Pure SwiftUI, feels like part of macOS. No web views, no Electron.
2. **brew is the source of truth.** Cellar never manipulates the Cellar/Caskroom directories directly; every mutation shells out to `brew`. The CLI and the GUI can coexist mid-task.
3. **Local-first, private.** No accounts, no telemetry, no backend. Network calls are limited to package metadata (formulae.brew.sh), cask artwork (CaskFlow / App-Fair), release notes (GitHub), and CVE feeds (OSV/NVD).
4. **Free forever.** All features free, ad-free.

## Features

- **Home** — greeting dashboard: what needs attention, installed snapshot, recent activity, favorites.
- **Search catalog** — instant search over the full formula and cask catalog, with kind, deprecation, and installed-state filters.
- **Discover** — App Store-style browse pages for casks *and* formulae: Featured, Top Charts (per-period install rankings), Recently Added, and curated Categories, with real app icons.
- **Installed / Favorites / Updates** — the inventory with lenses, bulk actions, and honest treatment of self-updating apps (they are never nagged as "outdated").
- **Services** — `brew services` status and control.
- **Health** — a weighted health score over outdated packages, advisories, orphans, cache size, and `brew doctor`.
- **Security** — CVE advisory coverage for installed packages, opt-in.
- **Cleanup** — per-package disk usage, old versions, and download cache, with safe remediation.
- **Taps & Brewfile** — tap management plus Brewfile import/export.
- **History** — a searchable log of every operation Cellar ran.

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon
- [Homebrew](https://brew.sh) installed — Cellar detects it and guides you if it is missing; it never installs Homebrew itself

## Install

Download the latest `Home-Cellar-<version>.zip` from
[Releases](../../releases), unzip it, and drag `cellar.app` to `/Applications`.

The build is notarized and stapled, so the first launch is a single ordinary
"Open" confirmation — no right-click workaround, and no network access needed to
get past Gatekeeper. Apple Silicon and macOS 26 only.

## Updates

Cellar updates itself with [Sparkle](https://sparkle-project.org), from an
EdDSA-signed appcast published alongside each release. The feed URL and the
public verification key are compiled into the app, so an update is only ever
installed if its signature matches the key the running copy already carries.

**Automatic checking is off by default.** A check is a network request, and
Cellar asks before making one: turn it on in **Settings → Updates**, or leave it
off and use **Cellar → Check for Updates…** whenever you want. The Settings card
also shows when the last check actually happened, and says so plainly when there
has never been one.

Prereleases are never offered.

## Building

Open `cellar.xcodeproj` in Xcode and run the `cellar` scheme, or:

```sh
xcodebuild -project cellar.xcodeproj -scheme cellar -configuration Debug build
```

The core logic lives in a local Swift package with its own test suites:

```sh
cd Packages/CellarCore && swift test
```

App-level and UI tests live in `cellarTests/` and `cellarUITests/`.

## Releasing

Pushing a `v*` tag is the only thing that publishes a release. CI builds an
arm64, Developer ID-signed, notarized and stapled `Home-Cellar-<version>.zip`
and attaches it to a GitHub Release; every gate runs before publication, so a
failed run publishes nothing.

The same job publishes the Sparkle appcast to GitHub Pages on a stable tag; a
prerelease tag publishes a release and no feed entry.

The runbook, prerequisites, version policy and entitlements rationale live in
[`RELEASING.md`](RELEASING.md).

## Architecture

The app target (`cellar/`) is a thin SwiftUI shell — composition root, stores, and views. Everything testable lives in `Packages/CellarCore`, split into single-purpose libraries with deliberately one-directional edges:

| Module | Responsibility |
|---|---|
| `BrewProcess` | Spawning and streaming the `brew` binary |
| `Catalog` | Catalog sync, search index, and Discover projections — never needs a `brew` binary |
| `BrewClient` | Installed inventory, mutations, services — the only module that sees both sides |
| `DiskUsage` | Per-package disk measurement |
| `SecurityKit` | Advisory (CVE) lookup and coverage |
| `ReleaseNotes` | Release-notes resolution via published repository URLs |
| `Persistence` | Favorites, notes, snoozes, history |

Product requirements and the design record live in [`PRD.md`](PRD.md); change specs live under `openspec/`.

## Third-party content

Cask category and added-date data originate from the [CaskHub](https://github.com/alielsokary/CaskHub) project (MIT), and the embedded update framework is [Sparkle](https://github.com/sparkle-project/Sparkle) 2.9.6 (MIT). See [`THIRD-PARTY.md`](THIRD-PARTY.md).
