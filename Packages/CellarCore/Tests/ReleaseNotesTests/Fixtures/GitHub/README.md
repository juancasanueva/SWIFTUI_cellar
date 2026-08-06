# GitHub release-notes captures

Captured **2026-08-06** from `api.github.com`, **unauthenticated**. No personal
access token was used for any capture and none is recorded anywhere in this
repository — the one exception, `error-401-unauthorized`, was captured with a
deliberately invalid token whose characters are recorded below precisely because
it is not a credential.

Written to the `Tests/BrewClientTests/Fixtures/Cleanup` standard, with **one
addition this capability needs**: every body has a sibling `*.headers.txt`
carrying the response headers verbatim. The rate-limit headers are load-bearing
— `RateLimitStatus` is parsed from *every* response, not only from a refusal —
so a capture without its headers would be half a capture.

## The exact request

Every live capture was issued as:

```
GET https://api.github.com/repos/{owner}/{repo}/releases?per_page=30
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

`per_page=30` is the value the shipped `GitHubReleaseNotesSource` defaults to.
It is a **parameter**, not a constant of the capability: every test asserts the
page bound against the injected `perPage`, never against a literal `30`. If the
bound ever changes, these fixtures describe the world at 30 and the tests still
read correctly, because none of them says "thirty".

## The streams

| Stream | Status | Source | Provenance |
|---|---|---|---|
| `releases-git-populated.json` | 200 | `sharkdp/hyperfine` | Live, **projected** (see below). 26 releases — the page did **not** fill its bound, so this is the fixture for an honest "no match" as opposed to a qualified one. Tags are `v`-prefixed (`v1.20.0`), which is what exercises the `v`-prefix candidate. |
| `releases-empty.json` | 200 | `git/git` | Live, verbatim. Five bytes: `[\n\n]\n`. Git publishes tags but no GitHub *releases*, so this is a real repository that really publishes none — the `.repositoryPublishesNoReleases` fixture, and not a hand-written `[]`. |
| `releases-page-full.json` | 200 | `BurntSushi/ripgrep` | Live, **projected**. Exactly **30** releases — the page filled its bound — with the oldest on the page `14.0.3`. Any installed version below that is a *qualified* miss (`pageWasFull`), never an absolute absence. Tags here carry **no** `v` prefix, which is the exact-tag candidate. |
| `releases-no-matching-tag.json` | 200 | `sharkdp/vivid` | Live, **projected**. 14 releases, and one of them (`v0.11.1-pre`) is a real `prerelease: true` record — the prerelease rule is exercised against a published one rather than an invented one. |
| `error-404-repo.json` + headers | 404 | `cellar-app-fixture/no-such-repository-9f3a` | Live, verbatim. A repository that does not exist. |
| `error-401-unauthorized.json` + headers | 401 | `sharkdp/hyperfine` with `Authorization: Bearer ghp_thisTokenIsDeliberatelyInvalid0000000000` | Live, verbatim. **Read its headers**: a real 401 carries *no* `x-ratelimit-*` header at all. That is why "a rejected token is not a rate limit" is a captured fact here and not an assumption — there is no budget or reset time to claim. |
| `error-403-ratelimit.json` + headers | 403 | **Authored** | Not live, and deliberately so: capturing a real 403 means exhausting the 60-request unauthenticated budget for this IP for an hour, which is a hostile thing to do to a shared address for one fixture. The body is GitHub's documented rate-limit payload and the header block is the *verbatim header set* of the live 200 capture above with `x-ratelimit-remaining: 0`, `x-ratelimit-used: 60`, a later `x-ratelimit-reset`, `cache-control: no-cache` and a corrected `content-length`. Everything a parser reads is real; only the values are set to the exhausted state. |
| `release-body-gfm.json` | — | **Authored** | Not live. A single release record in the projected shape below, whose `body` is a corpus assembled to carry, in one body, every construct `AttributedString(markdown:)` does not interpret: a GFM table, a task list, `~~strikethrough~~`, two `@mentions`, a bare autolink and an image reference. No real release carries all six at once; the alternative was six fixtures none of which proves that one *note* survives all of them. |
| `release-body-malformed.json` | — | **Authored** | Not live. The same shape, whose `body` is deliberately unparseable: unterminated emphasis, an unclosed code fence, a link and an image with no closing paren, a truncated table, unclosed raw HTML, and a block quote that jumps depth. |

### What "projected" means, exactly

A single `releases?per_page=30` response is **0.3–0.9 MB**, almost all of it the
`assets`, `author`, `uploader` and `*_url` fields this capability never decodes.
Shipping two megabytes of JSON to test seven fields would make the fixtures
unreviewable, so the three large captures are stored as a projection:

```python
KEYS = ["tag_name", "name", "body", "draft", "prerelease", "published_at", "html_url"]
projected = [{k: release.get(k) for k in KEYS} for release in captured]
json.dumps(projected, indent=2, ensure_ascii=False)
```

Every retained value is byte-identical to the capture, no element was dropped,
and no element was reordered — the array length is the array length GitHub
returned. The **only** transformation is removing keys the decoder does not read.
The SHA-256 of each original, unprojected capture is recorded below so the
projection is auditable rather than merely asserted:

| Stream | SHA-256 of the original capture | Original size |
|---|---|---|
| `releases-git-populated.json` | `b3efb12a8d53b20d5bf39633f47ec7bf670873f7902fbd21a1989b3ad520f5fa` | 687,056 B |
| `releases-page-full.json` | `305707122db494499c956f274d963b3a71706f5331236de9b611170b8bbd79e7` | 920,281 B |
| `releases-no-matching-tag.json` | `15831548652c55cff2f41032a4ed64fe2d83f9c27c4deff78e548f7182b2e90e` | 359,654 B |

`probe-manifest.txt` records the SHA-256 of every stream **as it ships**, and
`ReleaseNotesFixtureManifestTests` recomputes all of them on every run. A
silently re-saved fixture fails the suite before it can make a test pass.

## The digest-key trap

`RepositoryCandidates` reads **four URL fields and no digest field**. If you
later find yourself looking for a checksum in here, stop: this capability has no
use for one, and the fields are not where you would guess.

* A **formula**'s digest is `urls.stable.checksum` in Homebrew's published
  record. Slice 1 projected the formula **URLs only** and deliberately left the
  checksum out of scope. `FormulaSources` therefore carries `stableURL` and
  `headURL` and **nothing else** — its absence is a decision, not an oversight.
* A **cask**'s digest is the top-level `sha256`, which slice 1 *did* project, as
  `CaskInspection.declaredChecksum` (including the `no_check` literal that means
  the cask declares none).

So a missing checksum on a formula is correct and a missing one on a cask is a
bug. Nobody should "fix" the first by widening `CatalogPackage` — this slice
spends none of the snapshot footprint headroom, and `CatalogFootprintTests` runs
unchanged to prove it.

## The `*.headers.txt` standard

One file per body, same stem, `.headers.txt`. Contents are the response's status
line and headers exactly as the transport delivered them, with CRLF normalised
to LF and nothing else changed — no reordering, no case folding, no removal.
Header *names* are lowercase in the file because HTTP/2 delivers them that way;
`RateLimitStatus` therefore parses case-insensitively rather than depending on
that.
