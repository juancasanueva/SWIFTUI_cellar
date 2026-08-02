# BrewClient fixtures

## `installed-info.json`

A hand-trimmed excerpt of `brew info --installed --json=v2`, captured against
Homebrew 6.0.14. The envelope keeps the published `{"formulae": [...], "casks":
[...]}` shape; the records keep only the keys the projection reads plus a few it
deliberately drops, so the "we ignore the rest" claim is exercised rather than
assumed.

It is trimmed to one record per behaviour the inventory has to get right:

| Record | Kind | Why it is here |
|---|---|---|
| `wget` | formula | single keg, on request, matched by the catalog |
| `openssl@3` | formula | two installed kegs, neither may be dropped |
| `libunistring` | formula | dependency-only — no keg was installed on request |
| `git` | formula | outdated |
| `python@3.12` | formula | pinned, with a recorded pinned version |
| `private-tool` | formula | third-party tap, no catalog counterpart |
| `ghostty` | cask | self-updating (`auto_updates: true`), `installed` behind `version` |
| `firefox` | cask | self-updating and already current |
| `transmission` | cask | `auto_updates: null` — outdated on formula terms |
| `docker-desktop` | cask | pinned |

Re-capture with:

```sh
brew info --installed --json=v2 > /tmp/installed-info.json
```

then trim by hand. Do not paste a live dump in whole: it is ~660 KB and its
contents differ per machine, which makes every assertion in the suite unstable.
