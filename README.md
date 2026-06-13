# Magazzino

Shell-native project control center: organize projects by category, jump
between them with fuzzy search, scaffold/clone/move/archive them, keep git
status under control across every repo — all from one `mag` command, with an
interactive dashboard as the front door.

This folder is the definitive Magazzino. It supersedes the legacy single-file
version and the 2.0 preview.

## Highlights

- **Dashboard**: type `mag` and you are in a framed, full-screen view of
  every project — column-aligned list with status dots (dirty/unpushed/clean,
  from a background cache) and inline tags, views cycled with `Tab`
  (all/pinned/dirty/recent/archive), a two-line key legend, and a tabbed
  preview (`ctrl-o`: info / readme / todo / github). No subcommand needed for
  the daily 90%.
- **Pins, tags, descriptions**: `mag pin`, `mag tag`, `mag desc`. Pinned
  projects stay on top, `mag j @tag` filters by tag, descriptions show up in
  the preview.
- **Multiple roots**: keep `~/projects` and `~/work` (or more) in one picker
  with `mag config root add <path>`.
- **gh integration**: with the GitHub CLI installed, `mag clone` with no URL
  picks from your own repositories.
- **Plugins**: a `mag_cmd_<name>()` function in
  `~/.config/magazzino/commands/<name>.sh` becomes `mag <name>`.
- **Modular code**: `mag.sh` is a small loader; the implementation lives in
  focused modules under `lib/`.

## Requirements

- Bash or Zsh
- `git`, `fzf`
- Optional: `code` (or any editor via `mag config editor`), `gh`, `xdg-open`,
  `tmux` (sessions), `rg` (faster grep/todo), `bat`/`glow` (richer previews)

## Install

```bash
cd mag_final
chmod +x install.sh
./install.sh
```

The installer copies the app to `~/.local/share/magazzino/app/`, records the
repo path for `mag update`, and adds a `source` line to your shell rc. Any
older Magazzino install (legacy v1 or the 2.0 preview) is retired
automatically: its rc lines are removed, stale app files are cleaned up, and
recency/metadata from the preview are migrated. Config in
`~/.config/magazzino/` is reused unchanged.

Update later with `mag update`; uninstall with `./uninstall.sh [--keep-config]`.

## Dashboard keys

| Key | Action |
| --- | --- |
| `enter` | Jump to the selected project |
| `tab` | Cycle view: all → pinned → dirty → recent → archive |
| `ctrl-e` | Open it in your editor |
| `ctrl-t` | Open/switch to its tmux session |
| `ctrl-w` | Open its repo page in the browser |
| `ctrl-o` | Cycle preview tab: info → readme → todo → github |
| `ctrl-y` | Pin / unpin |
| `ctrl-a` | Archive (restore when in the archive view) |
| `ctrl-s` | Status across all repos |
| `ctrl-p` | Pull all repos (parallel) |
| `esc` | Quit |

## Commands

| Command | Alias | Description |
| --- | --- | --- |
| `mag` | | Open the dashboard (help when non-interactive) |
| `mag j [name\|@tag]` | `mag jump` | Jump: direct on unique match, picker otherwise, `@tag` filters |
| `mag -` | | Jump back to the last used project (ping-pong) |
| `mag c [name]` | `mag code` | Open a project in your configured editor |
| `mag web [name\|.]` | `mag w` | Open the repo page in the browser (`.` = current repo) |
| `mag n <cat> <name> [tpl]` | `mag new` | New project, optionally from a template name or URL |
| `mag clone [url] [cat]` | `mag cl` | Clone keeping history; `user/repo` shorthand; no URL + `gh` = pick |
| `mag mv <src> <dest>` | `mag m`, `mag move` | Move/rename a project or rename a whole category |
| `mag archive [name]` | `mag ar` | Move a project to `_archive` |
| `mag rm [name]` | `mag remove` | Delete permanently (interactive confirmation) |
| `mag pin [name]` | | Pin/unpin a project to the top of every list |
| `mag tag [name] [tags\|-d]` | | Tag a project (no args: list all tags) |
| `mag desc <name> [text\|-d]` | | Set/show/clear a one-line description |
| `mag s [j\|f]` | `mag status` | Pending changes; `j` jump into one, `f` fetch first |
| `mag pull [cat]` | `mag p` | Fast-forward pull across all repos (4 in parallel) |
| `mag refresh` | | Refresh the status-dot cache now |
| `mag config [path]` | `mag cfg` | Set the primary projects root |
| `mag config root add/rm/list` | | Manage multiple roots |
| `mag config editor <cmd>` | | Set the editor used by `mag c` |
| `mag config template ...` | | Manage named templates for `mag n` |
| `mag update` | `mag u` | Self-update from the source repo and reload |
| `mag changelog [v\|list]` | `mag ch` | Show release notes |
| `mag doctor` | `mag d` | Health checks (deps, roots, strays, plugins) |
| `mag version` / `mag aliases` / `mag help` | `v` / `a` / `h` | Info |

## Layout

Projects live at `<root>/<category>/<project>`. Archived projects move to
`<root>/_archive/<category>/<project>` and disappear from pickers and status;
restore with `mag mv '_archive/<cat>/<name>' '<cat>'`.

Data (recency, metadata) lives in `~/.local/share/magazzino/`; config in
`~/.config/magazzino/`.

## Philosophy

Intentionally small: shell-first, two hard dependencies, no daemon, no
database — flat text files you can read and edit. The dashboard is just fzf
used well.
