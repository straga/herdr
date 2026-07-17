# herdr — `hurt` fork

Fork of [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr) with one addition:
**a separator line between agent groups** in the sidebar's agents panel.

Branches:
- **`hurt`** (default) — upstream + our patch. This is what you want.
- `master` — untouched mirror of upstream, kept clean for syncing.
- `feature/agent-group-separators` — the patch alone, for a PR upstream.

## What's different from upstream

In the agents panel, grouped mode (`agent_panel_sort = "spaces"`), a thin `─` is drawn
where one workspace's agents end and the next workspace's begin. Without it the panel is a
flat list and group boundaries are invisible. Everything else is identical to upstream.

## Requirements (Apple Silicon macOS)

- macOS 14+, Apple Silicon (arm64). Intel is not covered — the build is arm64.
- **Rust 1.96.1** — pinned by `rust-toolchain.toml`, rustup pulls it automatically.
- **zig 0.15.2** — needed to build the vendored `libghostty-vt`:
  ```sh
  brew install zig@0.15
  ```
  If you already have zig 0.16+, it may fail: zig breaks `build.zig` between minor
  versions, and the vendored lib pins `minimum_zig_version = 0.15.2`.

## Build

```sh
git clone https://github.com/straga/herdr && cd herdr
cargo build --release
```

Takes ~1 minute; `build.rs` compiles `libghostty-vt` via zig, then links it in.
Result: `target/release/herdr` — a self-contained binary (only system frameworks, no
external libs to ship).

## Install

Put it on your PATH. `~/.local/bin` normally comes **before** `/opt/homebrew/bin`, so this
also overrides a brew-installed herdr if you have one:

```sh
mkdir -p ~/.local/bin
ln -sf "$PWD/target/release/herdr" ~/.local/bin/herdr
hash -r
which herdr        # expect ~/.local/bin/herdr, not /opt/homebrew/bin/herdr
```

A symlink (not a copy) keeps pointing at the build output — after a later
`cargo build --release` you get the new binary with no extra steps.

Revert at any time: `rm ~/.local/bin/herdr`.

## ⚠ If you already have herdr from brew

Brew installs a **LaunchAgent** that starts its own server and, with `KeepAlive`, restarts
it whenever it dies. Your fork client will just attach to that already-running **brew**
server — and you will see no separator, no matter how many times you rebuild. Disable it:

```sh
brew services stop herdr    # also unloads it from login autostart
```

Then start herdr yourself — the server comes up from the fork binary:

```sh
herdr
```

The brew binary stays on disk as a fallback; only its autostart is gone.

## Config

`~/.config/herdr/config.toml` is optional — the fork works with no config at all.

Relevant to this patch:

```toml
agent_panel_sort = "spaces"   # grouped mode; the separator is drawn only here
```

In `priority` mode there is deliberately no separator: groups interleave by attention
there, so a boundary would be meaningless.

**Don't copy our config blindly.** Some of it is specific to our herd tooling and will only
get in your way — e.g. `[session] resume_agents_on_restore = false`, which stops herdr from
restoring agents after a server restart (we relaunch them ourselves with our own markup).

## Update

```sh
git pull                   # hurt = fresh upstream + our patch
cargo build --release      # symlink already points here
```

To pick up upstream releases we sync `master` from upstream and merge it into `hurt`, so
`git pull` on `hurt` gives you both.
