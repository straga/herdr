# herdr — hurt fork

A fork of [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr) with two changes to the
agents sidebar: agents are grouped by workspace identity, and a separator line is drawn between
those groups.

Branches:

- `hurt` (default) is upstream plus our patch. This is the one you want.
- `master` is an untouched mirror of upstream, kept clean so syncing stays a fast-forward.
- `feature/agent-group-separators` is the patch on its own, for a PR upstream.

## What's different from upstream

In the agents panel, in grouped mode, agents are grouped by the identity of their workspace
rather than by worktree-space alone, so each ungrouped workspace forms its own group. A thin `─`
is then drawn where one group ends and the next begins. Without it the panel is one flat list and
you cannot see where a group stops. Nothing else is changed.

## Build

Upstream builds on Linux and macOS, x86_64 and aarch64. Native Windows is preview-only beta
upstream. Our patch is plain Rust UI code with no platform-specific parts, so it works
wherever upstream does.

Two things are needed everywhere:

- Rust 1.96.1. Pinned by `rust-toolchain.toml`, rustup installs it for you.
- zig 0.16.0, which builds the vendored `libghostty-vt` (`build.rs` calls it). zig breaks
  `build.zig` between minor versions, so the version to install is the one the vendored library
  asks for: `minimum_zig_version` in `vendor/libghostty-vt/build.zig.zon`. Read it there before
  installing — it moves when the vendored library is updated.

`cmake` and `ninja` belong to that vendored build, not to the Rust one. A tree whose
`vendor/libghostty-vt/.zig-cache` is already populated links the cached library and never calls
them: a release build on 2026-08-21 finished in 45s on a machine with neither installed. Install
them before the first build, or after clearing the zig caches.

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

## macOS keeps asking for permissions

macOS grants folder and automation access to a *signature*, not to a path. An unsigned binary
is identified by its hash, and the hash changes on every rebuild — so each build looks like a
new application and the dialogs come back. herdr runs its server detached from the terminal,
which makes the binary itself the subject of those grants rather than your terminal app.

Give it a stable signature once and the grants survive rebuilds:

```sh
./scripts/create-cert.sh      # once per machine
just build                    # builds, then signs
```

`create-cert.sh` puts a self-signed code-signing certificate in your login keychain. On the
first signing macOS asks whether `codesign` may use the key — answer "Always Allow", or every
build stops on that dialog.

If you have an Apple Developer ID, nothing extra is needed: `sign-binary.sh` prefers a
Developer ID Application certificate when the keychain holds one. `HERDR_SIGN_IDENTITY` picks a
specific identity, `HERDR_SIGN_IDENTIFIER` pins the identifier macOS keys the grants by — set
it if you have already answered those dialogs for a binary signed some other way.

Without any certificate the binary is signed ad-hoc and the script says so. That works, the
dialogs just keep coming back.

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

### Your own token in the agent row

The agent row is a list of tokens, and you can add one of your own. It takes two halves, and
they live in different places — which is the usual way this breaks.

The value comes from outside herdr. Whatever manages your panes reports it:

```sh
herdr pane report-metadata <pane_id> --source my-tool --token breed=🐑
```

The slot comes from your config. A token no row declares is never drawn, however faithfully
the value arrives:

```toml
[ui.sidebar.agents]
rows = [["state_icon", "workspace", "tab", "$breed"], ["agent"]]
```

Metadata is server-side and reaches every client attached to that endpoint. The row layout is
client-side and lives in the config of the machine you are looking from — so a second machine
shows the same agents without your token until its own config declares one.

Values are trimmed to 80 characters, and `--ttl-ms` expires a token on its own if the reporter
should stop having a say.

### Attaching from a second machine

The client renders the shell, so it reads the `config.toml` of the machine it runs on — not the
one on the machine it attaches to. Theme, palette, sidebar widths, status indicators and the
agent row layout are all resolved client-side (`ClientShellConfig::from_config`,
`src/client/shell/config.rs`). The endpoint sends nothing of the sort, with one exception: its
keybinding profile, and that only when the client asks for server bindings
(`server_keybindings_toml`, `src/protocol/wire.rs`).

This is deliberate upstream, not an oversight. `AGENTS.md`, section "Runtime/client boundary
guardrail", puts sidebar layout and token placement on the client and pane/agent metadata on the
server. Agent metadata therefore travels and custom row tokens do not: the value arrives, the
slot to print it in does not exist unless this machine's config declares one.

So the second machine starts on defaults and looks nothing like the first. Copy the presentation
part of your config across and it matches again — these sections:

```toml
[theme]
[ui]
[ui.toast]
[ui.sidebar.agents]
```

Leave the rest behind: `[session]` is server-side and means nothing on a client, and any
`[[keys.command]]` bound to a plugin that machine does not have becomes a dead key.

One more way to reach the same "why does this look wrong" moment: a debug build reads
`~/.config/herdr-dev/config.toml` while a release build reads `~/.config/herdr/config.toml`
(`app_dir_name()`, `src/config/io.rs`). `HERDR_CONFIG_PATH` overrides both.

Chrome you change by hand — sidebar width, section split, collapsed state, panel sort, collapsed
groups — is not in the config at all. It lives next to the config, under the state directory
(`~/.local/state/herdr/client-shell/local-<hash>.json` on Linux and macOS), keyed by a hash of the
endpoint socket path — so every endpoint you attach to remembers its own.

## Update

Our commits are replayed on top of an upstream release, so `hurt` stays a short, readable
series of our own changes rather than a chain of merges:

```sh
git fetch upstream --tags
git branch hurt-pre-<version>-<date> hurt   # insurance; a rebase is not undone by itself
git rebase <tag>                            # e.g. v0.8.2
cargo build --release                       # the symlink already points here
```

Target a release tag rather than `upstream/master`: a tag is reproducible, so a measurement taken
on it can be repeated. Verify afterwards that the patch survived — `git diff --stat <tag>..HEAD`
must still show the same files, and the separator has to be checked by eye in a live sidebar,
because it is UI and no build proves it renders.

A rebuilt binary changes nothing until the herdr **server** is restarted: the running server
keeps the old one in memory. `herdr server reload-config` reloads config, not the binary.
