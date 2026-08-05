# Cleanup runtime fixtures

These byte-exact files were captured from Homebrew `6.0.15-83-gd0b51c6`
during SDD work unit U0. The probe used this disposable prefix:

```text
/var/folders/v7/6grrq9ws0r373mpmxjjfx9fh0000gn/T/opencode/m3-cleanup-u0-probe/cellar-m3-cleanup-sentinel-prefix
```

The prefix contained `.cellar-m3-cleanup-sentinel`. Before every invocation,
the harness canonicalized the prefix, denied `/opt/homebrew` and `/usr/local`,
required that sentinel, and required `brew --prefix` to return the disposable
prefix. The Homebrew launcher and `Library/Homebrew` were copied into the
disposable prefix; the developer installations remained read-only.

## Captured commands

All commands used an empty environment plus the values recorded in
`probe-manifest.txt`. Cleanup commands set `HOMEBREW_NO_AUTOREMOVE=1`;
autoremove did not carry that variable.

| Capture | argv excluding `brew` | Exit | Observation |
|---|---|---:|---|
| `cleanup-global-dry-run` | `cleanup --dry-run` | 0 | Empty stdout; Homebrew API acquisition diagnostics on stderr. |
| `cleanup-full-dry-run` | `cleanup --dry-run --prune=all` | 0 | Two rows and Homebrew's reported total. |
| `autoremove-dry-run` | `autoremove --dry-run` | 0 | Byte-empty stdout and stderr: zero orphan candidates. |
| `cleanup-full` | `cleanup --prune=all` | 0 | Removed both disposable cache files and reported the total. |
| `contention-held` | `cleanup --prune=all` | 0 | A held Homebrew lock remained present. |
| `contention-released` | `cleanup --prune=all` | 0 | The same unheld lock was removed. |

The contention control used an OS advisory exclusive lock on
`cellar-m3-contention.lock`. `contention.txt` records the observed existence
checks before and after release. Empty `.stdout` and `.stderr` files are
intentional fixtures, not omitted captures.

## Capture integrity

The raw stream files are unnormalized and preserve their trailing newlines.
The two cleanup content fixtures deliberately retain the disposable absolute
path so parser tests can prove that output is treated as data, never argv.

```text
6071d6443d0abd26207541f06baa6f63fdc04d3019707a62d018f7ce8320f987  cleanup-full-dry-run.stdout
1d54d5ee1fc304ba6f7edd45c5f21d12b5de01ff3a1b34ba5fd3c19d981b82a0  cleanup-full.stdout
798744e3404ab7a8d895320cd4b83f989cd10f4b6b30c099a5c7f6b2f157774e  cleanup-global-dry-run.stderr
29e503db84ea934390cf2121292666bdd484f18e594736bb0341f71385dc0c95  contention.txt
e16204806d359c5b13d258a982c42fe09ad508810895ef8f8a5fb7bf48c10679  probe-manifest.txt
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  every intentional empty stream fixture
```
