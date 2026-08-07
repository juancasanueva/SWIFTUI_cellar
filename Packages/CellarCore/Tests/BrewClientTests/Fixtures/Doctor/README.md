# `brew doctor` fixtures

Two kinds of file live here, and they must never be confused:

- **Captured** — byte-exact streams written by the real `brew` binary during
  apply. Never edit them; re-capture and re-record the hashes instead.
- **Hand-authored** — the clean run and the hostile grouping fixture. They are
  inputs to the parser, never outputs of a probe, and each one carries a
  `HAND-AUTHORED.txt` marker **inside its own directory** as well as being
  declared here and in `probe-manifest.txt`. An unmarked hand-authored fixture is
  indistinguishable from a capture and must not ship.

`DoctorFixtureManifestTests` hashes every stream named in `probe-manifest.txt`
against the recorded SHA-256 and asserts both markers are present, so a silently
re-saved fixture fails the suite rather than quietly changing what a test
asserts.

## Captured: `brew doctor` with real warnings — `warnings-run/`

```text
HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew doctor
```

| Field | Value |
|---|---|
| Capture date | 2026-08-07 |
| Homebrew version | `6.0.15-125-g7372067` |
| Binary | `/opt/homebrew/bin/brew` |
| argv excluding `brew` | `doctor` |
| Environment | `HOMEBREW_NO_AUTO_UPDATE=1` — the same pin Cellar runs every read under |
| Exit status | **1** |
| Stability | both streams byte-identical across two consecutive runs (`cmp`-equal) |

| Stream | Provenance | Bytes |
|---|---|---:|
| `warnings-run/stdout.txt` | the subprocess's stdout, verbatim — **one byte, a bare newline** | 1 |
| `warnings-run/stderr.txt` | the subprocess's stderr, verbatim — the entire report | 622 |

**The stream split and the exit code are the point of this fixture**, and both
invert what the three shipped JSON payload sources require (`system-health`, "A
non-zero doctor exit is an ordinary outcome, and the document arrives on
stderr"):

- the run exited **1** because the machine has warnings, and that non-zero exit
  is the *informative* answer. A source that treated it as a command failure
  would discard the whole report;
- the report is on **stderr**. stdout carries a single `\n`. A source that read
  stdout only would publish nothing and call it clean; a source that refused a
  newline-only stdout as "blank or malformed" would refuse a perfectly ordinary
  run.

Both inversions are quarantined to this capability. `DoctorPayloadQuarantineTests`
asserts that `InstalledPayload`, `ServicesPayload` and `TapPayload` still reject
a non-zero exit and still admit stdout only.

### What the captured document contains

Counted from `warnings-run/stderr.txt`: 15 lines, of which 3 are the preamble
("Please note that these warnings are just used to help the Homebrew
maintainers…"), 2 are `Warning:` headlines, 7 are detail lines belonging to those
two blocks, and 3 are blank.

The preamble is Homebrew's own de-emphasis of its output, and it is why the
doctor input carries the **lowest** weight in the health score
(`HealthWeights.doctor`): brew itself says these warnings exist to help its
maintainers debug a reported issue.

Two shapes in it are load-bearing for the grammar:

- the second block's detail runs **across a blank line** — `Unexpected header
  files:` and its path arrive after an empty line, still inside the same block.
  A grammar that closed a block on a blank line would drop them;
- detail indentation is **not uniform** (`    gemini-cli` against `  ruby@3.1`),
  so nothing may key off a fixed indent width.

## Hand-authored: `clean-run/`

Marked in `clean-run/HAND-AUTHORED.txt`.

| Stream | Provenance | Bytes |
|---|---|---:|
| `clean-run/stdout.txt` | hand-authored; Homebrew's documented clean-run sentence | 30 |
| `clean-run/stderr.txt` | hand-authored; zero bytes | 0 |

**This could not be captured.** The machine this change was developed on has real
`brew doctor` warnings (probe U10, re-measured during apply), so exit 0 was not
reachable without changing that machine's Homebrew installation. The sentence is
transcribed from Homebrew's own success path, and nothing here claims this
machine ever printed it.

It is the fixture behind two rules that are easy to get wrong in opposite
directions: a clean run reports `0` warning groups and `0` unknown lines
**present rather than absent**, so "nothing was wrong" stays distinguishable from
"nothing was measured"; and a document carrying no `Warning:` block is *not*
automatically an unrecognised report — the ready sentence is what tells the two
apart from the bytes alone.

## Hand-authored: `odd-grouping/`

Marked in `odd-grouping/HAND-AUTHORED.txt`.

| Stream | Provenance | Bytes |
|---|---|---:|
| `odd-grouping/stdout.txt` | hand-authored; zero bytes | 0 |
| `odd-grouping/stderr.txt` | hand-authored; hostile, **invalid UTF-8 by construction** | 276 |

Five hostile shapes in one document: an indented detail line before any block has
opened, an empty `Warning: ` headline, two adjacent headlines with no detail
between them, a fourth headline that does carry detail, and a byte run that is
not valid UTF-8.

None of them may fail the acquisition. Each becomes a typed parse issue, the
undecodable run survives as **bytes** among the unknown lines with no replacement
character substituted, and the evidence is flagged partial — never empty, never
an error.

`odd-grouping/stderr.txt` is not valid UTF-8. Do not open it in an editor that
will "fix" the encoding on save; the manifest hash is what catches that if it
happens.

## Capture integrity

Recorded in `probe-manifest.txt` and asserted by `DoctorFixtureManifestTests`.
Trailing newlines are preserved as captured. `README.md` and `probe-manifest.txt`
are deliberately not hashed — a manifest cannot record its own digest, and this
prose changes whenever the reasoning does.
