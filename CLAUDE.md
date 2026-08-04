# Repository conventions

## Authorship

**All commits in this repository are authored by Shehan Feroze <msfrox@gmail.com> and nobody else.**

When committing here:

- Do **not** add `Co-Authored-By:` trailers of any kind.
- Do **not** add "Generated with …", "🤖", or any other tool advertising to commit
  messages, PR bodies, code comments, or documentation.
- Do **not** set `--author` or `GIT_AUTHOR_*` to anything other than the repo's
  configured identity.
- Do **not** add "written by an assistant" notes to source files.

This is enforced mechanically by `.githooks/commit-msg`, which strips such lines
before the commit is written. Do not disable, bypass (`--no-verify`), or edit that
hook to weaken it.

The single place this project acknowledges assistant involvement is one sentence in
`README.md`. That sentence is sufficient and complete — do not duplicate it elsewhere.

## Commit style

Short imperative subject, optional body explaining *why*. Example:

```
claude-usage: draw the weekly window as the ring, session as the fill

Waybar custom modules are text-only, so the two-window read had to live in a
rendered PNG fed through the image module instead of a glyph.
```

## Layout

| Path | Holds |
|---|---|
| `waybar/scripts/` | executable module backends (installed to `~/.config/waybar/scripts/`) |
| `waybar/modules/` | module definition snippets to merge into `modules.json` |
| `waybar/style/` | CSS snippets to append to the active theme's `style.css` |
| `quickshell/` | Quickshell apps — popups and panels (installed to `~/.config/quickshell/`) |
| `assets/` | icons and other static files |
| `docs/` | design notes and per-feature documentation |

`install.sh` symlinks the owned directories into place and prints the snippets that
need merging into ML4W-owned files.
