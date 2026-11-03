# herdr — hurt fork

A fork of [herdrdev/herdr](https://github.com/herdrdev/herdr), on top of release v0.9.5.

Branches:

- `hurt` (default) is upstream plus our changes. This is the one you want.
- `master` holds only upstream's commits, so syncing stays a fast-forward. It is not always
  current: compare it with upstream before relying on it.

## What's different from upstream

`git diff --stat v0.9.5..hurt` lists all of it.

**The agents panel.** In grouped mode agents are grouped by the identity of their workspace rather
than by worktree-space alone, so each ungrouped workspace forms its own group. A thin `─` is then
drawn where one group ends and the next begins. Without it the panel is one flat list and you
cannot see where a group stops.

**The macOS server.** Neither of these is in the v0.9.5 tag:

- automatically started servers run under a small `Herdr Server` app, so macOS has something to
  grant Local Network access to (upstream issue #808). See
  [Local Network access on macOS](#local-network-access-on-macos);
- the server keeps running when the terminal that started it quits (upstream #5236).

**Signing on macOS.** `scripts/create-cert.sh`, `scripts/sign-binary.sh`, and `just build` signs
after it builds. See [macOS keeps asking for permissions](#macos-keeps-asking-for-permissions).

## Build

Upstream builds on Linux and macOS, x86_64 and aarch64, and on Windows x86_64. This guide covers
Linux and macOS. The agents panel change is plain Rust UI code and works wherever upstream does; the
server and signing changes apply to macOS only.

Two things are needed everywhere:

- Rust 1.96.1. Pinned by `rust-toolchain.toml`; [rustup](https://rustup.rs) installs it for you on
  the first `cargo build`.
- zig 0.16.0, which builds the vendored `libghostty-vt` (`crates/ghostty-vt/build.rs` calls it,
  taking `$ZIG` if set and `zig` from your PATH otherwise). zig breaks `build.zig` between minor
  versions, so the version to install is the one the vendored library asks for:
  `minimum_zig_version` in `vendor/libghostty-vt/build.zig.zon`. Read it there before installing —
  it moves when the vendored library is updated.

On macOS you also need the Xcode command line tools (`xcode-select --install`): the top-level
`build.rs` compiles the `Herdr Server` launcher with `xcrun clang`, and the build stops without it.

`cmake` and `ninja` are what upstream CI installs for the build. A tree whose
`vendor/libghostty-vt/.zig-cache` is already populated links the cached library: a release build on
2026-08-21 finished in 45s on a machine with neither installed. Install them before the first
build, or after clearing the zig caches.

### Nix (any platform)

The repo ships a flake, so you need no toolchain at all:

```sh
nix build github:straga/herdr/hurt     # binary lands in ./result/bin/herdr
nix run   github:straga/herdr/hurt
```

### macOS

```sh
xcode-select --install       # skip if the command line tools are already there
brew install zig@0.16 cmake ninja just
export PATH="$(brew --prefix zig@0.16)/bin:$PATH"    # versioned formulae are not linked

git clone https://github.com/straga/herdr && cd herdr
just build                   # cargo build --release --locked, then signs the binary
```

`brew install zig` gives you the newest zig, which is not the one the vendored library asks for.
The `export` lasts for this shell: repeat it, or put it in your shell rc, before the next build.
Without a certificate `just build` signs ad-hoc and says so. See
[macOS keeps asking for permissions](#macos-keeps-asking-for-permissions).

### Linux

The build tools are the ones upstream CI installs:

```sh
sudo apt-get update
sudo apt-get install -y cmake ninja-build musl-tools
# zig 0.16.0: from your package manager, or https://ziglang.org/download/

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

The build takes about a minute. `crates/ghostty-vt/build.rs` compiles `libghostty-vt` with zig and
links it in, and you get `target/release/herdr` (or `target/<triple>/release/herdr`). The binary is
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

## Local Network access on macOS

Read this on a Mac, or your tools will fail in a way that looks like a network problem.

macOS lets a program reach other machines on your local network only with the Local Network
permission. A bare binary has no `Info.plist`, so the system offers no switch for it, and everything
started under the herdr server is cut off. The sign is `No route to host` from a command inside
herdr while the same command works outside it. Not every tool is hit: on 0.9.3 a Python script and
`bun` were refused while `curl` and `nc` to the same host got through. So an MCP server or a script
can fail while your quick `curl` says the network is fine.

On this branch an automatically started server runs under a small signed app, `Herdr Server`, which
holds the permission for everything under the server. The server creates it the first time it
starts automatically, in `$XDG_DATA_HOME/herdr/server-app-v1/Herdr Server.app` (by default
`~/.local/share/herdr/...`). Updating herdr keeps that app rather than replacing it, because a new
signature would invalidate the grant. Do not copy it between machines: the permission is granted on
each machine separately.

The first run on a machine:

```sh
herdr server stop    # this ends the processes in your panes
herdr
```

macOS then asks about local network access for **Herdr Server**. Choose **Allow**.
A person has to press it, in a GUI login session, including on a remote Mac. An old server cannot be
repaired by a live handoff, which is why it is stopped here rather than reloaded.

To check:

- System Settings > Privacy & Security > Local Network shows Herdr Server switched on;
- `ps -axo lstart,command | grep 'Herdr Server'` shows the server running under the app;
- a command that failed before now reaches the host from a pane.

Start the server with plain `herdr`. An explicit `herdr server` keeps the context of whatever
launched it and does not go through the app.

Whether the grant survives a later server restart without asking again is **not verified**. The app
exists so that it should, but we have not yet seen it happen. If macOS asks again after a restart,
the grant did not hold.

## macOS keeps asking for permissions

macOS grants folder and automation access to a *signature*, not to a path. An unsigned binary
is identified by its hash, and the hash changes on every rebuild — so each build looks like a
new application and the dialogs come back. Local Network access is the exception: `Herdr Server`
holds it, as described above, and a signature on the binary does not grant it.

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

### Signing without a person at the screen

The login keychain unlocks only inside a GUI session. From SSH `codesign` fails with
`errSecInternalComponent`, and from a process with no window, such as anything inside herdr, it waits
forever for a password dialog nobody can see. For those, keep the certificate in a separate build
keychain with a known password. The scripts do not create it: make it with `security
create-keychain` and import your identity into it. Then name it in `~/.config/herdr/signing.env`,
which `sign-binary.sh` reads by itself:

```sh
HERDR_SIGN_KEYCHAIN=$HOME/Library/Keychains/build.keychain-db
HERDR_SIGN_KEYCHAIN_PASSWORD_FILE=$HOME/.config/secrets/build-keychain-password
```

The same two names work as environment variables. With a build keychain configured the script takes
a Developer ID Application identity from it, or the one in `HERDR_SIGN_IDENTITY`. It stops with an
error if it finds neither, rather than falling back to the login keychain and hanging.
`create-cert.sh` puts its certificate in the login keychain, so it does not serve here as it stands.

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
git remote add upstream https://github.com/herdrdev/herdr   # once
git fetch upstream --tags
git branch hurt-pre-<version>-<date> hurt   # insurance; a rebase is not undone by itself
git rebase --onto <new-tag> <old-tag> hurt  # e.g. --onto v0.9.6 v0.9.5
just build                                  # the symlink already points here
```

`--onto` matters: upstream puts release tags on release branches, so the old tag is not in the
history of the new one, and a plain `git rebase <new-tag>` carries upstream's own commits along with
ours.

Target a release tag rather than `upstream/master`: a tag is reproducible, so a measurement taken
on it can be repeated. Verify afterwards that the patch survived — `git diff --stat <tag>..HEAD`
must still show the same files, and the separator has to be checked by eye in a live sidebar,
because it is UI and no build proves it renders.

A rebuilt binary changes nothing until the herdr **server** is restarted: the running server
keeps the old one in memory. `herdr server reload-config` reloads config, not the binary. Stopping
the server with `herdr server stop` ends the processes in your panes.
