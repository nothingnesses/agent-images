# `withNix` implementation plan

Based on [analysis.md](analysis.md). Implements single-user Nix with `sandbox = false` behind an opt-in `withNix` flag.

## Status: implemented and tested

All steps below have been completed. Manual testing confirmed:
- `nix --version` works
- Store DB is populated (140 paths registered)
- `/nix/store` is writable by the agent user (container overlay)
- `nix-shell -p hello --command hello` fetches and runs packages
- `nix shell nixpkgs#hello -c hello` works via flake registry
- `NIX_PATH` is set so legacy `<nixpkgs>` lookups work

## Decisions applied

| Issue | Approach |
|---|---|
| Writable `/nix/store` | Container overlay provides write access; no chown on store needed |
| Daemon | None - single-user mode |
| Rootless Podman UIDs | Sidestepped by single-user mode |
| Build sandbox | `sandbox = false` by default |
| Nix version | nixpkgs-pinned default + `nixPackage` parameter override |
| `nix develop` / direnv | `nix develop` works out of the box; direnv documented as `extraPackages` example |
| Store ownership | `chown -R ./nix` in `fakeRootCommands` (only affects `./nix/var`; `./nix/store` doesn't exist at build time) |
| Store registration | `includeNixDB` from nixpkgs' `buildLayeredImage` (upstream `mkDbExtraCommand`) |
| `NIX_PATH` | Set to `nixpkgs=${pkgs.path}` so `nix-shell -p` works |
| Image size | Benchmark in CI + approximate number in README |

## Implementation details

### `lib/mkAgentImage.nix`

New parameters:

```nix
withNix ? false,
nixPackage ? pkgs.nix,
nixExperimentalFeatures ? [ "nix-command" "flakes" ],
```

When `withNix` is true:

1. **`nixConf`**: A `writeTextDir` derivation that produces `/etc/nix/nix.conf` with `sandbox = false` and the configured experimental features.

2. **`nixDeps`**: `[ nixPackage nixConf ]` appended to `allPackages`.

3. **`includeNixDB = withNix`**: Passed to `buildLayeredImage`. This uses nixpkgs' built-in `mkDbExtraCommand` which runs in `extraCommands` (before `fakeRootCommands`) and:
   - Sets `NIX_REMOTE=local?root=$PWD`
   - Runs `nix-store --load-db` with `closureInfo` registration
   - Resets registration times for reproducibility
   - Creates GC roots for all contents

4. **`fakeRootCommands`**: Appends `chown -R ${uidStr}:${uidStr} ./nix` to grant the agent user ownership of `/nix/var` (the only `/nix` subtree present at build time).

5. **`config.Env`**: Adds `NIX_CONF_DIR=/etc/nix` and `NIX_PATH=nixpkgs=${pkgs.path}`.

### `flake.nix`

- `nixTestImage` in the `let` block: opencode + `withNix = true`, exported as `packages.*.nix-test-image`
- `apps.smoke-test-nix`: Offline checks (nix version, store DB, store writability, path readability)
- `apps.smoke-test-nix-install`: Network checks (runtime `nix-shell` install, `nix develop`)

### `README.md`

New "Using Nix Inside Containers" section covering:
- How to enable, example definition
- `nixPackage` and `nixExperimentalFeatures` overrides
- direnv as `extraPackages` example
- Known limitations (no build sandbox, image size)
- Host store mount optimisation
- Smoke test commands

### `.github/workflows/ci.yml`

New `smoke-test-nix` job with image size delta reporting.

## File change summary

| File | Change |
|---|---|
| `lib/mkAgentImage.nix` | New parameters, conditional Nix setup via `includeNixDB`/`nixConf`/`chown`/env vars; `which` added to `defaultBasePackages` |
| `flake.nix` | `nixTestImage`, `smoke-test-nix`, `smoke-test-nix-install` |
| `README.md` | New "Using Nix Inside Containers" section |
| `.github/workflows/ci.yml` | `smoke-test-nix` job + size reporting |

## Key discovery during implementation

`buildLayeredImage` places store paths in separate image layers - `./nix/store` does not exist in the `fakeRootCommands` working directory. This made the original "shallow chown" approach impossible (can't chown what doesn't exist). However, at container runtime, the overlay filesystem merges all layers and the writable layer allows the agent user to create new store paths. The `includeNixDB` parameter from nixpkgs handles store registration correctly via `extraCommands` (which runs before `fakeRootCommands`), using `NIX_REMOTE=local?root=$PWD`.

## Other changes made during implementation

- **`which` added to `defaultBasePackages`**: Discovered during smoke test development that `which` was missing. Added to base packages and updated the README's base packages list.
- **`nix develop` test uses Nix-interpolated `${system}`**: `builtins.currentSystem` was removed in newer Nix. The `smoke-test-nix-install` test flake uses `${system}` interpolated by Nix at eval time (from `eachDefaultSystem`) instead.
