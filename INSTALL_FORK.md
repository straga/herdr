# herdr — `hurt` fork

Fork of [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr) with one addition:
**a separator line between agent groups** in the sidebar's agents panel.

Branches:
- **`hurt`** (default) — upstream + our patch. This is what you want.
- `master` — untouched mirror of upstream, kept clean for syncing.
- `feature/agent-group-separators` — the patch alone, for a PR upstream.

## What's different from upstream

In the agents panel, in grouped mode, a thin `─` is drawn
where one workspace's agents end and the next workspace's begin. Without it the panel is a
flat list and group boundaries are invisible. Everything else is identical to upstream.

## Build

Upstream builds on **Linux and macOS** (both x86_64 and aarch64); native Windows is
preview-only beta upstream — our patch is plain Rust UI code and platform-neutral, so it
follows whatever upstream supports.

Common to every platform:
- **Rust 1.96.1** — pinned by `rust-toolchain.toml`, rustup pulls it automatically.
- **zig 0.15.2** — builds the vendored `libghostty-vt` (`build.rs` calls it).
  zig breaks `build.zig` between minor versions and the vendored lib pins
  `minimum_zig_version = 0.15.2`, so **0.16+ will not do**.

### Nix (any platform)

The repo ships a flake — no toolchain setup needed:

```sh
nix build github:straga/herdr/hurt     # binary at ./result/bin/herdr
nix run   github:straga/herdr/hurt
```

### macOS

```sh
brew install zig@0.15 cmake ninja
git clone https://github.com/straga/herdr && cd herdr
cargo build --release
```

### Linux

Build tools mirror what upstream CI installs:

```sh
sudo apt-get update
sudo apt-get install -y cmake ninja-build musl-tools
# zig 0.15.2 — from your package manager, or https://ziglang.org/download/

git clone https://github.com/straga/herdr && cd herdr
cargo build --release
```

Upstream ships Linux binaries built against **musl** (statically linked). To match that:

```sh
rustup target add x86_64-unknown-linux-musl
cargo build --release --locked --target x86_64-unknown-linux-musl
```

For an aarch64 (musl) build you also need the cross toolchain and its linker:

```sh
sudo apt-get install -y gcc-aarch64-linux-gnu crossbuild-essential-arm64
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc
cargo build --release --locked --target aarch64-unknown-linux-musl
```

Takes ~1 minute; `build.rs` compiles `libghostty-vt` via zig and links it in. Result:
`target/release/herdr` (or `target/<triple>/release/herdr`) — self-contained, nothing extra
to ship alongside.

**If a build fails after switching zig versions or targets**, clear the zig caches (CI does
this on every run):

```sh
rm -rf .zig-cache vendor/libghostty-vt/.zig-cache vendor/libghostty-vt/zig-out
```

## Install

Put it on your PATH — e.g. `~/.local/bin`:

```sh
mkdir -p ~/.local/bin
ln -sf "$PWD/target/release/herdr" ~/.local/bin/herdr
hash -r
which herdr        # must point at ~/.local/bin/herdr
```

If `which` still shows another herdr (e.g. a package-managed one), your PATH prefers that
directory — put `~/.local/bin` ahead of it in your shell rc, or install elsewhere.

A symlink (not a copy) keeps pointing at the build output — after a later
`cargo build --release` you get the new binary with no extra steps.

Revert at any time: `rm ~/.local/bin/herdr`.

## ⚠ If you already have herdr from brew (macOS)

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

`~/.config/herdr/config.toml` is optional — **the fork needs no config at all** for the
separator to work.

The separator is drawn in **grouped** mode, which is already the default
(`agent_panel_sort` defaults to `spaces`). Nothing to set up.

If you flip the panel to **priority** (the toggle in the agents panel header), the
separator disappears — by design: groups interleave by attention there, so a boundary
would be meaningless.

## Update

```sh
git pull                   # hurt = fresh upstream + our patch
cargo build --release      # symlink already points here
```

To pick up upstream releases we sync `master` from upstream and merge it into `hurt`, so
`git pull` on `hurt` gives you both.
