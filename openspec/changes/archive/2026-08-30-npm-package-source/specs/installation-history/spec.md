# Delta for installation-history

Existing capability — `openspec/specs/installation-history/spec.md` (**9 requirements / 33 scenarios**).
This delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**; every shipped requirement is byte-identical.
The capability becomes **10 requirements / 37 scenarios**.

## ADDED Requirements

### Requirement: npm entries store the npm identity, namespaced verbs and a source-aware presentation

An npm operation MUST write exactly one entry at its terminal outcome on the shipped terms, carrying the
package identity `(npm, name)` through the existing `kindRaw` string `npm` with no schema migration, one
of exactly two namespaced verbs — `npmUpgrade`, `npmUninstall` — the version moved from and to when
both are known, the outcome and the exact argv. The stored argv MUST remain display-only. Presentation
MUST derive a source badge from the stored kind, MUST prefix the displayed command with `npm`, and MUST
word the outcome label for npm (an npm exit status, an npm permissions failure) rather than for
Homebrew. Search MUST match `npm`, the bare terms `upgrade` and `uninstall`, the package name and the
argv, case-insensitively. A build without the npm kind MUST decode such rows as absent rather than fail
or misattribute them.

#### Scenario: Each npm verb writes one identity-bearing entry

- GIVEN `install -g typescript@latest` (from `5.6.2` to `5.7.0`) and `uninstall -g corepack` each reaching a
  terminal outcome
- WHEN the history is read
- THEN exactly two entries exist carrying `npmUpgrade` and `npmUninstall`, identity kind `npm`, their
  argvs and outcomes, and the upgrade carries from `5.6.2` to `5.7.0`
- Verification: `unit`

#### Scenario: Presentation is source-aware

- GIVEN a failed `npmUpgrade` entry with exit status `243` and an `EACCES` classification
- WHEN it is presented
- THEN the command reads `npm install -g typescript@latest`, the badge names npm, and the outcome label
  names npm permissions rather than Homebrew
- Verification: `unit`

#### Scenario: npm entries are searchable by source, verb and name

- GIVEN one `npmUpgrade` entry for `typescript` and one brew `upgrade` entry for `wget`
- WHEN the history is searched for `NPM`, then `typescript`, then `upgrade`
- THEN the first two return only the npm entry and the third returns both
- Verification: `unit`

#### Scenario: A stored npm row degrades safely without the kind

- GIVEN a persisted row with `kindRaw` `npm`
- WHEN it is decoded by a decoder that does not know that kind
- THEN it decodes as absent, nothing throws, and no brew identity is inferred
- Verification: `unit`
