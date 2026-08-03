# Delta for brew-execution

Existing capability — `openspec/specs/brew-execution/spec.md` (6 requirements / 20 scenarios).

Delta summary: **1 MODIFIED requirement — 3 scenarios (1 carried forward and edited, 2 added)**. The
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED. 6 requirements / 20 scenarios → **6 requirements / 22 scenarios**.

**Why this capability is in this slice at all.** The shipped requirement names `HOMEBREW_COLOR=0`
verbatim (`openspec/specs/brew-execution/spec.md:11`) and states the intent as disabling colour.
`HOMEBREW_COLOR` is a *force-colour* boolean in brew (`Library/Homebrew/env_config.rb:249-252`,
declared with `disabled_by: :HOMEBREW_NO_COLOR`): **any** value counts as set, `"0"` included. The
shipped requirement therefore mandates the exact opposite of its own stated intent, and a three-way
`od -c` probe confirmed it — under `HOMEBREW_COLOR=0` the captured bytes carry `\033[34m==>\033[0m`
even with stdout redirected to a file, while `HOMEBREW_NO_COLOR=1` comes back clean (Engram `#7179`).
This cannot be fixed by a code-only change; the requirement text has to change with it.

**Explicitly NOT in this delta:**

- **"Terminal result and exit handling"** already carries the typed unknown-operation result and its
  scenario — M2-3 follow-up **S1** was closed by `m3-hardening-prelude` (M3-0, archived 2026-08-03).
  The umbrella explore's §3 row still lists it as this milestone's brew-execution work; that row is
  stale. Re-modifying it here would be a no-op block with a regression risk and is deliberately
  omitted.
- **"Serialized mutations with concurrent reads" (BE5) is unchanged.** Every new command family this
  slice introduces is a mutation and inherits the existing FIFO gate, the read/mutation split, the
  SIGINT→SIGTERM escalation and the SIGKILL ban verbatim.
- **"Verbatim line-oriented output streaming" (BE2) is unchanged and is load-bearing here.** Its
  scenario requires a line containing ANSI bytes to be delivered byte-identically. ANSI suppression
  is therefore an *environment* concern, never a filtering one — the amended requirement below says
  so explicitly so no future change "fixes" colour by stripping escape bytes in the core and quietly
  breaks BE2.

## MODIFIED Requirements

### Requirement: Normalized brew environment

Every `brew` invocation MUST run with `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_COLOR=1`,
`HOMEBREW_NO_EMOJI=1`. `HOMEBREW_NO_INSTALL_FROM_API` MUST NOT be set (default API mode).

`HOMEBREW_COLOR` MUST NOT be set to any value, including `"0"`. It is a force-colour boolean whose
mere presence enables ANSI output regardless of value, so setting it to a falsy-looking string
produces the opposite of the intended effect. Colour MUST be disabled through `HOMEBREW_NO_COLOR`
only.

Suppression MUST happen at the source. Because captured output is required to be byte-identical to
what `brew` emitted, the capability MUST NOT strip, filter, rewrite or otherwise post-process escape
bytes out of a captured line in order to satisfy this requirement. Consequently no ESC byte (`0x1B`)
MUST appear in output captured from a `brew` invocation run with this environment.
(Previously: the requirement mandated `HOMEBREW_COLOR=0`, which forces ANSI on rather than off, and
said nothing about where suppression must happen.)

#### Scenario: Environment applied to every invocation

- GIVEN a runner backed by a recording process spawner
- WHEN any command is executed
- THEN the recorded environment contains `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_COLOR=1` and
  `HOMEBREW_NO_EMOJI=1` with those exact values
- AND contains no `HOMEBREW_NO_INSTALL_FROM_API` key

#### Scenario: The force-colour key is never set at any value

- GIVEN the pinned brew environment
- WHEN its keys are enumerated
- THEN no `HOMEBREW_COLOR` key is present, at `"0"` or at any other value

#### Scenario: No ANSI escape byte survives capture

- GIVEN a `brew` invocation executed with the pinned environment and its output captured
  non-interactively
- WHEN every captured line's bytes are inspected
- THEN no line contains the ESC byte `0x1B`
- AND no line was altered, trimmed or re-encoded to achieve that
