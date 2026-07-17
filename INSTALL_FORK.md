# herdr — hurt fork

A fork of [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr) with one addition: a
separator line between agent groups in the sidebar.

Branches:

- `hurt` (default) is upstream plus our patch. This is the one you want.
- `master` is an untouched mirror of upstream, kept clean so syncing stays a fast-forward.
- `feature/agent-group-separators` is the patch on its own, for a PR upstream.

## What's different from upstream

In the agents panel, in grouped mode, a thin `─` is drawn where one workspace's agents end
and the next workspace's begin. Without it the panel is one flat list and you cannot see
where a group stops. Nothing else is changed.

## Build

Upstream builds on Linux and macOS, x86_64 and aarch64. Native Windows is preview-only beta
upstream. Our patch is plain Rust UI code with no platform-specific parts, so it works
wherever upstream does.

Two things are needed everywhere:

- Rust 1.96.1. Pinned by `rust-toolchain.toml`, rustup installs it for you.
- zig 0.15.2, which builds the vendored `libghostty-vt` (`build.rs` calls it). zig breaks
  `build.zig` between minor versions and the vendored library requires
  `minimum_zig_version = 0.15.2`, so 0.16+ will not work.

### Nix (any platform)

The repo ships a flake, so you need no toolchain at all:

```sh
nix build github:straga/herdr/hurt     # binary lands in ./result/bin/herdr
nix run   github:straga/herdr/hurt
```

### macOS

```sh
brew install zig@0.15 cmake ninja
git clone https://github.com/straga/herdr && cd herdr
cargo build --release
```

### Linux

The build tools are the ones upstream CI installs:

```sh
sudo apt-get update
sudo apt-get install -y cmake ninja-build musl-tools
# zig 0.15.2: from your package manager, or https://ziglang.org/download/

git clone https://github.com/straga/herdr && cd herdr
cargo build --release
```

Upstream ships its Linux binaries against musl, statically linked. To match:

```sh
rustup target add x86_64-unknown-linux-musl
cargo build --release --locked --target x86_64-unknown-linux-musl
```

An aarch64 musl build also needs the cross toolchain and its linker:

```sh
sudo apt-get install -y gcc-aarch64-linux-gnu crossbuild-essential-arm64
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc
cargo build --release --locked --target aarch64-unknown-linux-musl
```

The build takes about a minute. `build.rs` compiles `libghostty-vt` with zig and links it
in, and you get `target/release/herdr` (or `target/<triple>/release/herdr`). The binary is
self-contained, there is nothing else to ship with it.

If a build fails after you switch zig versions or targets, clear the zig caches. CI does
this on every run:

```sh
rm -rf .zig-cache vendor/libghostty-vt/.zig-cache vendor/libghostty-vt/zig-out
```

## Install

Put the binary on your PATH, for example in `~/.local/bin`:

```sh
mkdir -p ~/.local/bin
ln -sf "$PWD/target/release/herdr" ~/.local/bin/herdr
hash -r
which herdr        # must point at ~/.local/bin/herdr
```

If `which` still shows a different herdr, such as a package-managed one, then your PATH
prefers that directory. Put `~/.local/bin` ahead of it in your shell rc, or install
somewhere else.

Use a symlink rather than a copy. It keeps pointing at the build output, so after the next
`cargo build --release` you already have the new binary.

To undo all of this: `rm ~/.local/bin/herdr`.

## If you installed herdr from brew (macOS)

Read this one. It costs an hour otherwise.

Brew installs a LaunchAgent that starts its own herdr server and, because of `KeepAlive`,
restarts it whenever it dies. Your fork client attaches to that running brew server, so you
see no separator no matter how often you rebuild. Stopping the server does not help either,
launchd brings it straight back.

Turn the service off:

```sh
brew services stop herdr    # also removes it from login autostart
```

Then start herdr yourself, and the server comes up from the fork binary:

```sh
herdr
```

The brew binary stays on disk as a fallback. Only its autostart is gone.

## Config

`~/.config/herdr/config.toml` is optional. The separator needs no configuration.

It is drawn in grouped mode, which is already the default (`agent_panel_sort` defaults to
`spaces`). If you switch the panel to priority, the separator goes away on purpose: groups
interleave by attention there, so a boundary would mean nothing.

## Update

```sh
git pull                   # hurt = current upstream plus our patch
cargo build --release      # the symlink already points here
```

We keep `master` in sync with upstream and merge it into `hurt`, so `git pull` on `hurt`
brings you both.
