# Brewfile bundle fixtures

Two kinds of file live here, and they must never be confused:

- **Captured** — byte-exact streams written by the real `brew` binary during
  work unit U6 and re-captured during apply. Never edit them; re-capture and
  re-record the hashes instead.
- **Hand-authored** — adversarial and shape fixtures written for this change.
  They are inputs to the parser, never outputs of a probe.

`BrewfileFixtureManifestTests` hashes every stream named in `probe-manifest.txt`
against the recorded SHA-256, so a silently re-saved fixture fails the suite
rather than quietly changing what a test asserts.

## Captured: `brew bundle dump`

```text
/opt/homebrew/bin/brew bundle dump --file <tmp>/Brewfile --force --formula --cask --tap
```

| Field | Value |
|---|---|
| Capture date | 2026-08-07 |
| Homebrew version | `6.0.15-125-g7372067` |
| Binary | `/opt/homebrew/bin/brew` |
| argv excluding `brew` | `bundle dump --file <tmp>/Brewfile --force --formula --cask --tap` |
| `--file` value | a disposable directory under the session scratchpad, created for this capture and removed after it |
| Exit status | **0** |

| Stream | Provenance | Bytes |
|---|---|---:|
| `dump-file.brewfile` | the file `brew` wrote at `--file`, verbatim | 5268 |
| `dump-stdout.txt` | the subprocess's stdout, verbatim — **empty on purpose** | 0 |
| `dump-stderr.txt` | the subprocess's stderr, verbatim | 399 |

**The stream split is the point of this fixture.** The run exited `0` and still
wrote 399 bytes to stderr: an unrelated `libtiff`/`webp` circular-dependency
warning, plus Homebrew API acquisition diagnostics. A source that treated a
non-empty stderr as failure would report this successful export as an error, and
a source that concatenated the streams would put a warning inside the published
Brewfile. Neither is permitted (`brewfile-management` BF8).

Note also that the document is written to the **file**, not to stdout. stdout is
byte-empty for a successful dump, so a source reading stdout would publish
nothing at all and call it success.

### What the captured document contains

Counted from `dump-file.brewfile`: 9 `tap` lines, 59 `brew` lines, 11 `cask`
lines, 69 `#` comment lines, 148 lines total, and **no** line that is not one of
those or blank.

Four shapes in it are load-bearing for the grammar (`brewfile-management` BF3,
BF5) and are why the parser is written the way it is:

- `# …` description comments are emitted **without** `--describe` on this
  Homebrew version — 69 of them. Counting them as skips would make every real
  round-trip look lossy, so the grammar ignores them without counting.
- `tap "n", "url"` — the URL second positional, pinned by U9 and present here on
  `cloudmanic/spice-edit` and `gentleman-programming/tap`.
- `trusted:` on both `tap` **and** `brew` lines — `trusted: { casks: [...] }`
  and `trusted: true`. It is parsed as grammar, surfaced as a claim by the
  file's author, and confers nothing (BF5).
- `brew "user/repo/token"` — tap-prefixed package names from third-party taps,
  10 of them. `MutationName.isSafe` accepts `/`, so these are ordinary entries;
  degrading them to skips would drop every third-party package of a real dump.

One option hash appears, `brew "dotnet@9", link: true`, and it is a counted
`unsupportedOption` skip: installing a stripped entry is not what the file's
author wrote (BF4).

## Why `dump` is the only `bundle` subcommand Cellar may construct

Probe **U8**, re-verified first-hand on the same binary during apply
(2026-08-07, Homebrew `6.0.15-125-g7372067`):

```text
Brewfile:
    File.write("<tmp>/marker.txt", "evaluated")
    brew "wget"

/opt/homebrew/bin/brew bundle check --file <tmp>/Hostile.brewfile
exit 1
stdout: (empty)
stderr: … brew bundle can't satisfy your Brewfile's dependencies.
```

After the run, `<tmp>/marker.txt` existed and contained `evaluated`.

`brew bundle check` — what a PRD-shaped "read-only diff preview" would reach for
— **evaluates the Brewfile's Ruby**. Pointing it at a file a user supplied runs
a stranger's code. That is why `dump` is the only `bundle` subcommand this
capability may construct, why `--file` is always a path Cellar itself created,
and why the import path parses bytes and spawns nothing at all
(`brewfile-management` BF1, BF2).

The marker file and its Brewfile were written under the session scratchpad and
removed afterwards. They are deliberately **not** committed: a fixture that runs
when a tool reads it is not a fixture.

## Hand-authored: adversarial and shape fixtures

| File | Purpose |
|---|---|
| `hostile-ruby.brewfile` | `File.write`, backticks, `$(…)`, `;`, `system(…)`, `#{ENV[…]}`, `Foo.bar`, and a trailing `if OS.mac?` — every one a counted skip, none of it ever evaluated (BF2, TM1, TM2) |
| `mixed-kinds.brewfile` | the ten unsupported entry kinds, `#` comments, blanks, a trailing comma, both quote styles, `brew "user/repo/token"`, and `postinstall:`/`args:`/`link:` option hashes (BF3, BF4) |
| `trusted-taps.brewfile` | U9's three `trusted:` lines **verbatim**, including the URL-positional form (BF5) |
| `undecodable.brewfile` | invalid UTF-8 in exactly one line; the surrounding lines are well-formed (BF2) |
| `empty.brewfile` | zero bytes — a typed empty parse, distinct from a read failure (BF2) |

`undecodable.brewfile` is not valid UTF-8 by construction. Do not open it in an
editor that will "fix" the encoding on save; the manifest hash is what catches
that if it happens.

## Capture integrity

Recorded in `probe-manifest.txt` and asserted by
`BrewfileFixtureManifestTests`. Trailing newlines are preserved as captured.
