# npm fixtures

Captured output of the real `npm` binary, used by the npm payload, decoder and
outcome tests. `probe-manifest.txt` records, per file, the exact command, its
exit code, whether the bytes are a verbatim capture or hand-authored, and every
edit applied.

## Why these files exist

npm's exit codes do not mean what Homebrew's mean. `npm outdated -g --json`
exits `1` on its normal success path — "something is outdated" — and
`npm ls -g --json` exits `1` while still printing a complete document when a
global package has an unsatisfied dependency (`ELSPROBLEMS`). The three brew
JSON payload sources refuse any non-zero exit and are right to; these fixtures
pin the npm rule as a separate, tested contract instead of a comment.

## Reading them

Each fixture is a single stream, named after it: `*.stdout`, `*.stderr` or
`*.json` for a stdout document. A case that spans both streams is two files
sharing a stem (`ls-g-problems.stdout`, `ls-g-problems.stderr`).

## Amending them

Re-capture rather than edit by hand. If a case cannot be produced without
modifying the machine's real global packages, hand-author it and say so in
`probe-manifest.txt` with the reason — the manifest is the record of which bytes
are evidence and which are a model.
