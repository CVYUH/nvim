# One rust-analyzer for nvim + every Claude Code session

## The problem

Every Claude Code session spawns its **own** rust-analyzer. On this workspace each grows to
**~7–11GB**. Three parallel sessions → ~30GB. Add nvim's own analyzer on a 46GB box and it OOMs.
Claude Code has no way to share one — no memory cap, no idle shutdown, no reuse setting. Upstream
has been asked repeatedly ([#28673](https://github.com/anthropics/claude-code/issues/28673),
[#26752](https://github.com/anthropics/claude-code/issues/26752),
[#64536](https://github.com/anthropics/claude-code/issues/64536)) and never answered.

## The fix

[**lspmux**](https://codeberg.org/p2502/lspmux) — a daemon that keeps one language server and
multiplexes every client onto it. (Successor to `ra-multiplex`, archived Oct 2025.)

`rust-analyzer` in this directory is a **shim**: a small bash script named `rust-analyzer` so that
nvim and Claude Code — both of which just run the bare command `rust-analyzer` — hit it instead of
the real binary, and get routed to the daemon. **The filename is the mechanism; it cannot be
renamed.**

`pin-workspace-root.py` sits between the shim and the daemon and rewrites one field of the LSP
handshake. Without it the daemon still runs, but nvim and Claude Code land on **separate**
analyzers — see the next section, which is the part that actually determines whether sharing
happens.

## How the sharing key works (read this before debugging a split)

lspmux keys instances on `InstanceKey { server, args, env, workspace_root }` (`client.rs`), and
resolves `workspace_root` in this order (`select_workspace_root`, `client.rs:276`):

1. `initialize.workspaceFolders[0].uri`
2. `initialize.rootUri` *(deprecated)*
3. `initialize.rootPath` *(deprecated)*
4. the client process **cwd** — *last resort, only if the client announces no root at all*

**The launch directory is almost never the key.** Both nvim and Claude Code always announce a root,
so #1 wins and cwd is never consulted. What split them here was that Claude Code's plugin announces
the **nearest Cargo root** (`.../cvyuh-systems/am2`) while `rust.lua` pins `root_dir` to the repo
root — two keys, two ~10GB analyzers, silently.

`pin-workspace-root.py` fixes it at the only layer that can: it rewrites `workspaceFolders`/
`rootUri`/`rootPath` to the repo root for any client whose announced root falls **inside** the repo,
then execs `lspmux client`. Clients outside the repo pass through untouched, so unrelated Rust
projects keep their own analyzers. This is safe because rust-analyzer auto-discovers every Cargo
root beneath the repo root — exactly what nvim has always asked for.

Note `env` is also part of the key, though `pass_environment` defaults to `[]`, so no environment
variable is forwarded and env is always empty. If you ever set `pass_environment`, any client
differing in those vars gets its own analyzer.

## Wiring pattern

Every config this repo owns lives **in the repo** and is reached from its well-known path by
a **symlink** — never edited in place under `~/.config`. That is what makes it versioned,
reviewable, and present on a fresh clone. The precedent is nvim itself:

```sh
ln -s ~/code/cvyuh-systems/nvim/nvchad ~/.config/nvim
```

| canonical file (in repo) | well-known path | how |
|---|---|---|
| `nvim/nvchad/` | `~/.config/nvim` | symlink |
| `nvim/rust-lsp/rust-analyzer` | *(none — found via PATH order)* | PATH |
| `nvim/rust-lsp/rust-analyzer.toml` | `~/.config/rust-analyzer/rust-analyzer.toml` | symlink |
| `nvim/rust-target/config.toml` | `<repo>/.cargo/config.toml` | symlink |
| `nvim/rust-lsp/lspmux.service` | `~/.config/systemd/user/lspmux.service` | **copy — see below** |

**When a symlink is impossible, copy it and say so in both places** — a header comment in the
file itself *and* the doc — because a copy drifts and nothing will tell you. `lspmux.service`
is the only such case here: systemd treats a symlink in its unit directory as an enablement
link, so `systemctl --user disable` **deletes it** and the unit silently becomes `not-found`
until the next reboot surfaces it. It loads, starts and survives `daemon-reload` first, which
is exactly what makes it a trap. Verified 2026-07-28.

After editing `lspmux.service` here, re-copy it and `systemctl --user daemon-reload`.

## Install

### 1. Install lspmux

```sh
cargo install lspmux          # binary lands at ~/.cargo/bin/lspmux
```

### 2. Put this directory on PATH, ahead of ~/.cargo/bin

In `~/.zshrc`:

```sh
export PATH="$HOME/code/cvyuh-systems/nvim/rust-lsp:$PATH"
```

⚠️ **Order is the whole trick.** The real analyzer lives in `~/.cargo/bin`. This directory must come
**before** it or the shim never runs. Verify in a **new** shell:

```sh
which rust-analyzer      # -> ~/code/cvyuh-systems/nvim/rust-lsp/rust-analyzer
```

Also note `/usr/local/bin` does **not** work as a home for this — it sits *behind* `~/.cargo/bin`.

### 3. Run the daemon

Foreground, in its own terminal:

```sh
lspmux server
```

Or as a systemd user service, so it survives terminal close, logout and reboot.
`lspmux.service` in this directory is ready to install — systemd only reads
`~/.config/systemd/user/`, so it has to be **copied** there (not symlinked — see
"Wiring pattern"):

```sh
cp lspmux.service ~/.config/systemd/user/
systemctl --user daemon-reload          # systemd does not notice new files by itself
systemctl --user enable --now lspmux    # enable = start at login; --now = also start it right now
loginctl enable-linger $USER            # optional: keep running after you log out
```

⚠️ **Stop any foreground `lspmux server` first** — it holds port 27631, so the service would fail to
bind and `Restart=always` would retry forever.

Check on it:

```sh
systemctl --user status lspmux      # expect: active (running)
journalctl --user -u lspmux -f      # its logs, in place of watching a terminal
```

Undo: `systemctl --user disable --now lspmux && rm ~/.config/systemd/user/lspmux.service`

**If the daemon is down nothing breaks** — the shim probes port 27631 and falls back to running the
real analyzer directly, bypassing the pinner entirely. You silently lose sharing (memory goes back
up), you don't lose Rust.

### 4. Nothing to install for the workspace-root pin

`pin-workspace-root.py` lives beside the shim and is found relative to it (`readlink -f "$0"`), not
via PATH. It needs only python3. Uninstall it by reverting the `PINNER` line in the shim — you drop
back to plain `lspmux client`, which works but re-splits nvim and Claude Code.

### 5. Link the user-level analyzer config

`rust-analyzer.toml` in this directory carries the `linkedProjects` bound (see the ⚠️ under
"Proven", below — without it the vendored workspaces in `_inspirations/` get indexed and the
analyzer balloons). rust-analyzer only reads it from `~/.config`, so link it there:

```sh
mkdir -p ~/.config/rust-analyzer
ln -s ~/code/cvyuh-systems/nvim/rust-lsp/rust-analyzer.toml ~/.config/rust-analyzer/rust-analyzer.toml
```

Symlink, not a copy — this file must stay in sync with `rust.lua`, and a copy will drift.

## Verify it works

```sh
lspmux status                       # instance list + attached clients
for p in $(pgrep -x rust-analyzer); do
  awk -v p=$p '/^VmRSS/{printf "analyzer %s: %.2f GB\n", p, $2/1048576}' /proc/$p/status
done
```

Expect **one** analyzer, parented to `lspmux server`, with every client listed under it — and
critically, `path:` reading your **repo root** (`.../cvyuh-systems`), the same for **every**
instance. A `path:` pointing at a subdirectory (`.../am2`) means the pin is not being applied and
you are about to grow a second analyzer. Confirm the shim is routing through the pinner:

```sh
grep -c PINNER "$(which rust-analyzer)"     # -> 2
```

The pinner logs every handshake to `~/.local/state/lspmux-pin/pin.log`:

```sh
tail -f ~/.local/state/lspmux-pin/pin.log
```
```
15:45:18 pid=570133 INIT  linkedProjects=NO
15:45:18 pid=570133 PIN   /home/<you>/code/cvyuh-systems/am2 -> /home/<you>/code/cvyuh-systems
```

`PIN` = root rewritten, `NOOP` = already at repo root, `PASS` = left alone (outside the repo, or no
root announced). `INIT linkedProjects=NO` flags a client that would auto-discover if it initialized
the instance first — harmless now that `rust-analyzer.toml` (this directory, symlinked into
`~/.config`) provides the bound, but it tells you who is in the race.

**Not stderr, deliberately.** The pinner's stderr is inherited from whoever spawned the shim (nvim,
or a Claude session), so it never reaches the lspmux journal — the journal only carries the
*analyzer's* stderr, which lspmux forwards explicitly. Logging to stderr made "did the pin fire?"
unanswerable.

One file, one rule: **never exceed 512KB.** On overflow the oldest lines are dropped from the front
(cut at a newline, so the file never starts mid-record). No generations, no age-out — the ceiling is
the whole policy, so there is nothing to rotate, prune or clean up.

⚠️ **Use `pgrep -x rust-analyzer` (exact name).** `pgrep -af rust-analyzer` also matches
`lspmux client --server-path .../rust-analyzer` and counts **shims as analyzers** — a false positive
that already caused one wrong "sharing is broken" conclusion.

## Proven (workspace-root pin, measured 2026-07-18, 46GB box)

- **A client launched from `am2`, announcing `am2` as its workspace root — the exact Claude Code
  behaviour that caused the split — now lands on an instance keyed at the repo root.** Verified by
  driving a real `initialize` handshake through the shim and reading back `lspmux status`.
- **Pin logic covers the cases that matter**: subdir root rewritten; already-repo-root left alone;
  `rootUri` with no `workspaceFolders` rewritten; path **outside** the repo untouched; client
  announcing no root left to the cwd fallback; non-`initialize` and unparseable messages forwarded
  byte-identical.
- **The split was never about launch directory.** The shim that created the `am2` instance was
  itself running with cwd = repo root.

## Proven (sharing, measured 2026-07-17, Claude Code 2.1.211, 46GB box)

- **nvim + a Claude Code session share one analyzer.** Instance held at 9.55GB; the `LSP` call that
  normally costs ~10GB and ~2min of indexing cost **0GB and returned instantly** off the warm index.
- **A fresh nvim reuses the warm instance** — same pid, no re-index.
- **No plugin, no `settings.json`, no session restart.** Claude Code's official
  `rust-analyzer-lsp` plugin hardcodes `command: "rust-analyzer"` → resolves through the shim. PATH
  is read at server spawn, so a session already running picks it up.
- ⚠️ **`linkedProjects` is REQUIRED — do not "simplify" it away.** An earlier version of this
  README claimed auto-discovery made it unnecessary. That is wrong and would cost you ~30GB: the
  repo also contains `_inspirations/`, **12 vendored third-party Cargo workspaces** (kanidm, sqlx,
  redis-rs, ldap3, scylla-cdc-rust, …). They are read-only reference and spin up if initiated, so
  scanning from the repo root drags every one of them into the index. The explicit list is the only
  thing keeping them out.
  This is also why yesterday's `am2`-keyed Claude instance sat at 1.40GB while nvim's repo-root one
  hit 9.81GB — nvim's list bounded it.
  **`rust-analyzer.toml` in this directory is the single source for the list** (12 crates).
  It exists because pinning everyone to the repo root means a Claude session — which sends no
  settings — could initialize the shared instance first and auto-discover; the user-level config
  makes the bound hold whoever wins that race, and also sets `files.excludeDirs` for
  `_inspirations`. `rust.lua` **reads** that array at startup instead of keeping a copy, so add or
  remove a crate in the TOML and nvim follows. If it cannot read the file it says so at
  `ERROR` level and sends no `linkedProjects`, rather than failing quietly.
  This was two hand-synced lists until 2026-07-28 — do not reintroduce the second one.

## Gotchas

- **Launch directory does not matter** (as of `pin-workspace-root.py`, and it was never the real
  key — see "How the sharing key works"). `cd am2 && claude` is fine.
- **Idle instances are reaped after 5 minutes, automatically.** lspmux ships a compiled-in
  `defaults.toml` with `instance_timeout = 300` and `gc_interval = 10`. The absence of
  `~/.config/lspmux/config.toml` does **not** mean there is no reaper — it means the defaults apply.
  Observed: nvim's client disconnected at 15:15:28, GC killed the 9.81GB instance at 15:16:58
  (`idle=306`, SIGKILL). Idle counts from **last use**, not from disconnect.
- **But an instance with a client still attached is never reaped** (`instance.rs:377` requires
  `clients.is_empty()`). A forgotten background session — e.g. a day-old `claude bg-spare` — pins
  its analyzer forever. If memory is held and nothing seems to be using it, look for a stale client
  in `lspmux status` before blaming the reaper.
- **The first client to create an instance defines its config for everyone.** LSP `initialize` runs
  once per server; later clients inherit whatever the first one asked for, regardless of their own
  settings. Harmless here (auto-discovery), but it means whoever touches Rust first silently sets
  the project view.
- **`kill <analyzer_pid>` is a legitimate stopgap** — reclaims the RAM immediately, nothing fights
  back, cost is the next re-index.
- **`[cargo] targetDir = true` in `rust-analyzer.toml` is load-bearing — do not drop it.** The repo
  shares ONE `target/` across all crates (`nvim/rust-target/config.toml`, symlinked to
  `<repo>/.cargo/config.toml`), and one target dir means one build-dir lock. That setting gives the
  analyzer `target/rust-analyzer/` so its `cargo check` never blocks — or gets blocked by — the
  `cargo watch -x run` in the kind dev pods, which mount the same repo path.
- **Free mitigation, unrelated to any of this:** `permissions.deny: ["LSP"]` in sessions not doing
  Rust navigation. Nothing spawns until the `LSP` tool is called, so a session that never uses it
  costs 0GB.

## Related

`nvchad/lua/configs/lang/rust.lua` — nvim's rust-analyzer config. Auto-attach is **off** by default
(`:RAStart` / `:RAStop`), which predates this and is still a reasonable belt-and-braces.
It sets no `cmd`, so it resolves through PATH and picks up the shim for free.
