# PR #4 review analysis

PR: https://github.com/nothingnesses/agent-images/pull/4
Issue: https://github.com/nothingnesses/agent-images/issues/2

Two comments were left on the PR by `0xferrous`. This document analyses approaches to address each.

---

## Comment 1: `default.nix` wrapper for build-time parameters

0xferrous proposes a [`default.nix` wrapper](https://gist.github.com/0xferrous/23662ac5177be2e18ccbd1e42090444d) that would allow building images with build-time parameters:

```bash
nix build -f . pi --arg withNix true
```

The gist defines a `default.nix` that imports the flake, iterates over agent names, and exposes a `mkImageFor` function per agent with configurable arguments (`withNix`, `tag`, `extraPackages`, `extraEnv`, `user`, `uid`, `workingDir`, `basePackages`, `nixPackage`, `nixExperimentalFeatures`).

<details>
<summary>Gist contents: <code>default.nix</code></summary>

```nix
let
  flake = builtins.getFlake (toString ./.);
  system = builtins.currentSystem;
  pkgs = import flake.inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  lib = pkgs.lib;
  agents = flake.inputs.llm-agents.packages.${system};
  mkAgentImage = flake.lib.mkAgentImage { inherit pkgs lib; };

  agentNames = builtins.filter (name: builtins.hasAttr name agents) (builtins.attrNames flake.packages.${system});

  mkImageFor =
    name:
    {
      withNix ? false,
      tag ? "latest",
      extraPackages ? [ ],
      extraEnv ? { },
      user ? "agent",
      uid ? 1000,
      workingDir ? "/workspace",
      basePackages ? null,
      nixPackage ? pkgs.nix,
      nixExperimentalFeatures ? [ "nix-command" "flakes" ],
    }:
    let
      agent = agents.${name};
    in
    mkAgentImage (
      {
        name = "agent-images/${name}";
        inherit
          agent
          tag
          extraPackages
          extraEnv
          user
          uid
          workingDir
          withNix
          nixPackage
          nixExperimentalFeatures
          ;
        entrypoint = [ agent.meta.mainProgram ];
      }
      // lib.optionalAttrs (basePackages != null) {
        inherit basePackages;
      }
    );
in
lib.genAttrs agentNames mkImageFor
// {
  inherit mkAgentImage pkgs lib agents;
}
```

</details>

### Approach A: Add the `default.nix` as proposed

A thin wrapper that calls into the flake via `builtins.getFlake`, enabling `nix build -f . pi --arg withNix true`.

- **Pro:** Ergonomic for non-flake workflows and one-off builds with toggled options
- **Con:** Uses `builtins.getFlake (toString ./.)` which requires `--impure` evaluation
- **Con:** Second entry point to maintain alongside `flake.nix` - risk of drift
- **Con:** Duplicates the per-agent image definitions that the flake already generates

### Approach B: Expose `withNix` variants directly in flake outputs

Add outputs like `pi-nix` alongside `pi`, so users run `nix build .#pi-nix`.

- **Pro:** Pure flake evaluation, no `--impure` needed
- **Pro:** Single source of truth, no second file to maintain
- **Pro:** Discoverable via `nix flake show`
- **Con:** Doubles the number of package outputs (25+ agents x 2)
- **Con:** Doesn't generalise to other args (`extraPackages`, custom `uid`, etc.)

### Approach C: Do nothing - point users to `mkAgentImage` in their own flake

Users who want customised builds already have the exposed `lib.mkAgentImage`. Document this as the intended path for custom configurations.

- **Pro:** Zero maintenance burden, already works today
- **Pro:** Fully flexible - users control all parameters
- **Con:** Requires users to write their own flake to consume `mkAgentImage`, though this is a standard Nix workflow

---

## Comment 2: Permission errors

0xferrous reports three permission failures when running a `withNix` image under Podman.

<details>
<summary>Reproduction steps and full output</summary>

1. Build image: `nix build -f . pi --arg withNix true`
2. Load image: `podman load -i ./result`
3. Run the container:

```
$ : podman run --rm -ti -v ./:/workspace --entrypoint bash localhost/agent-images/pi-nix:latest
bash-5.3$ ls
LICENSE  README.md  default.nix  flake.lock  flake.nix	lib  plans  result  tests
bash-5.3$ pwd
/workspace
bash-5.3$ nix shell nixpkgs#tmux
error: creating directory '/nix/store/.links': Permission denied
bash-5.3$ nix-shell -p tmux
error: creating directory '/tmp/nix-shell-21-1581260928': Permission denied
bash-5.3$ nix-shell -p tmux --command tmux
error: creating directory '/tmp/nix-shell-38-3190018454': Permission denied
bash-5.3$
bash-5.3$ pi
node:fs:1363
  const result = binding.mkdir(
                         ^

Error: EACCES: permission denied, mkdir '/home/agent/.pi/agent/sessions/--workspace--'
    at mkdirSync (node:fs:1363:26)
    at getDefaultSessionDir (file:///nix/store/6bz1pigcdn949qj60l1djslaqnj1df75-pi-0.58.3/lib/node_modules/@mariozechner/pi-coding-agent/dist/core/session-manager.js:212:9)
    at SessionManager.create (file:///nix/store/6bz1pigcdn949qj60l1djslaqnj1df75-pi-0.58.3/lib/node_modules/@mariozechner/pi-coding-agent/dist/core/session-manager.js:961:35)
    at createAgentSession (file:///nix/store/6bz1pigcdn949qj60l1djslaqnj1df75-pi-0.58.3/lib/node_modules/@mariozechner/pi-coding-agent/dist/core/sdk.js:69:69)
    at main (file:///nix/store/6bz1pigcdn949qj60l1djslaqnj1df75-pi-0.58.3/lib/node_modules/@mariozechner/pi-coding-agent/dist/main.js:639:53) {
  errno: -13,
  code: 'EACCES',
  syscall: 'mkdir',
  path: '/home/agent/.pi/agent/sessions/--workspace--'
}
```

</details>

### Error 1: `/nix/store/.links` - Permission denied

`nix shell nixpkgs#tmux` fails trying to create `/nix/store/.links` (used by Nix's `auto-optimise-store` for hard-linking identical store paths).

**Root cause:** `/nix/store` lives in content layers created by `buildLayeredImage` - these are root-owned. The `chown -R ./nix` in `fakeRootCommands` (`mkAgentImage.nix:59`) only affects `/nix/var` (the DB layer from `includeNixDB`), not `/nix/store` itself since store paths are placed in separate layers.

The CI test at `nix.bats:27` does `touch /nix/store/.write-test` - this may pass under Docker or rootful Podman (where the container's writable overlay layer allows writes to root-owned directories) but fail under **rootless Podman** where UID remapping changes effective ownership.

### Error 2: `/tmp/nix-shell-*` - Permission denied

`nix-shell -p tmux` fails creating temporary directories in `/tmp`.

**Root cause:** `/tmp` is `chmod 1777` at `mkAgentImage.nix:86` in `fakeRootCommands`. This creates a customisation layer with the correct permissions. But in rootless Podman, the UID namespace mapping can cause the sticky-bit directory to still deny writes if the mapped UID doesn't match.

### Error 3: `/home/agent/.pi/agent/sessions/` - Permission denied

The `pi` agent fails creating its session directory under the agent user's home.

**Root cause:** Same pattern - `/home/agent` is `chown`'d at `mkAgentImage.nix:87`, but the effective ownership may not translate correctly through rootless Podman's UID remapping.

### Likely common root cause

All three errors are consistent with **rootless Podman UID remapping**. The image sets uid 1000 inside the container, but rootless Podman maps that to a high subordinate UID on the host, causing overlay permission mismatches. This needs to be confirmed by reproducing the errors.

### Approach A: Entrypoint wrapper that fixes permissions at runtime

Add a shell script as the entrypoint that runs permission fixups before `exec`'ing the agent.

- **Pro:** Works regardless of container runtime or UID mapping
- **Pro:** Can handle `/nix/store`, `/tmp`, and `$HOME` in one place
- **Con:** Requires the container to start as root (or use `--privileged`), then `su`/`exec` to the agent user
- **Con:** Adds complexity and breaks the current clean single-user model
- **Con:** Slower startup

### Approach B: Use `buildImage` instead of `buildLayeredImage`

Single-layer image where `fakeRootCommands` has full control over all paths including `/nix/store`.

- **Pro:** `chown` on `/nix/store` works since everything is in one layer
- **Pro:** Simplest fix for the store ownership problem
- **Con:** Loses layer caching - every rebuild redownloads the entire image, not just changed layers
- **Con:** Larger image transfer sizes

### Approach C: Extra customisation layer for `/nix/store` ownership + `auto-optimise-store = false`

Keep `buildLayeredImage` but ensure the customisation layer (which sits on top of content layers) creates `/nix/store` with correct ownership. Also add `auto-optimise-store = false` to `nix.conf` to prevent `.links` creation.

- **Pro:** Targeted fix, minimal change to existing architecture
- **Pro:** Keeps layer caching benefits
- **Con:** Need to verify that the overlay ordering respects the customisation layer's directory ownership over the content layers' directory entries
- **Con:** `auto-optimise-store = false` increases disk usage for stores with many duplicate files

### Approach D: Document `--userns=keep-id` for rootless Podman

If the root cause is rootless Podman UID remapping, document that users should run with `podman run --userns=keep-id` which maps the host UID directly to the container UID.

- **Pro:** Zero code changes, documentation only
- **Pro:** Addresses the root cause for rootless Podman users
- **Con:** Puts the burden on the user to know the right flags
- **Con:** Doesn't fix the `/nix/store` ownership issue (still root-owned in image layers)
- **Con:** Only helps Podman users, not Docker users who may hit similar issues

### Approach E: Move writable state under `$HOME`

Set `TMPDIR=/home/${user}/tmp`, add `store = /home/${user}/.nix/store` to `nix.conf`, ensuring all writable paths live under the user's home directory.

- **Pro:** Everything is under `$HOME` - guaranteed writable regardless of container runtime
- **Pro:** No runtime fixups, no entrypoint wrappers
- **Con:** Non-standard store location breaks assumptions (pre-registered DB paths, `NIX_PATH`, etc.)
- **Con:** User-local store approach is less tested in the Nix ecosystem
- **Con:** `TMPDIR` change could affect other tools besides Nix

---

## Reproduction results

Attempted to reproduce 0xferrous's permission errors across four scenarios:

1. `nix build .#nix-test-image` (flake) + `podman run` (rootless).
2. Same with `--userns=keep-id`.
3. Same with `-v ./:/workspace`.
4. `nix build -f . pi --arg withNix true --impure` (0xferrous's `default.nix`) + `podman run`.

**All four passed without errors.** `/nix/store`, `/tmp`, and `$HOME` were writable in every case, and `nix shell` / `nix-shell` both succeeded. The permission errors could not be reproduced locally.

This confirms the issue is specific to 0xferrous's rootless Podman UID mapping configuration, not a bug in the image build. The defensive code changes (Approaches A-C, E for Comment 2) are unnecessary since there is no build-time layer ordering issue.

---

## Recommendation

### For Comment 1 (default.nix)

**Approach C** (do nothing, document `mkAgentImage`) is the lowest-maintenance option. If ergonomic one-off builds are important, **Approach B** (expose `-nix` variants in flake outputs) is preferable to the `default.nix` wrapper since it avoids the `--impure` requirement and keeps a single source of truth.

### For Comment 2 (permissions)

**Approach D only** (document `--userns=keep-id`). Since the errors could not be reproduced, no code changes are needed. The issue is specific to 0xferrous's Podman configuration. Documentation and a local test suite are sufficient.

---

## Outcome

### Comment 1

Chose **Approach C**. Replied to 0xferrous pointing to `lib.mkAgentImage` and the Custom Images section in the README, with a working flake example for their use case.

### Comment 2

Chose **Approach D**. Added `--userns=keep-id` documentation to the README under Known Limitations. Added a Podman-only local test suite (`nix-userns.bats`) that verifies `/nix/store`, `/tmp`, and `$HOME` writability under `--userns=keep-id`. Extended the `run_in` test helper to accept optional runtime flags. Replied to 0xferrous with reproduction results and troubleshooting steps, asked them to report back.
