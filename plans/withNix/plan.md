# `withNix` implementation plan

Based on [analysis.md](analysis.md). Implements single-user Nix with `sandbox = false` behind an opt-in `withNix` flag.

## Decisions applied

| Issue | Approach |
|---|---|
| Writable `/nix/store` | Single-user Nix with store owned by agent user |
| Daemon | None - single-user mode |
| Rootless Podman UIDs | Sidestepped by single-user mode |
| Build sandbox | `sandbox = false` by default |
| Nix version | nixpkgs-pinned default + `nixPackage` parameter override |
| `nix develop` / direnv | `nix develop` works out of the box; direnv documented as `extraPackages` example |

## Steps

### 1. Add new parameters to `mkAgentImage`

In `lib/mkAgentImage.nix`, add to the function signature:

```nix
withNix ? false,
nixPackage ? pkgs.nix,
nixExperimentalFeatures ? [ "nix-command" "flakes" ],
```

### 2. Build the Nix configuration file

When `withNix` is true, create a `nix.conf` derivation:

```nix
nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
  sandbox = false
  experimental-features = ${lib.concatStringsSep " " nixExperimentalFeatures}
'';
```

### 3. Include Nix packages conditionally

Add the Nix CLI and its runtime dependencies to `allPackages` when `withNix` is true:

```nix
nixPackages = lib.optionals withNix [ nixPackage nixConf ];
allPackages = [ agent ] ++ basePackages ++ extraPackages ++ nixPackages;
```

`nixPackage` (default `pkgs.nix`) provides both `nix` and legacy commands (`nix-shell`, `nix-build`, etc.).

### 4. Set up Nix store and DB in `fakeRootCommands`

When `withNix` is true, append to `fakeRootCommands`:

1. Create required Nix directories:
   ```bash
   mkdir -p ./nix/var/nix/db
   mkdir -p ./nix/var/nix/gcroots
   mkdir -p ./nix/var/nix/profiles
   mkdir -p ./nix/var/nix/temproots
   mkdir -p ./nix/var/nix/userpool
   mkdir -p ./nix/var/nix/daemon-socket
   ```

2. Register the image's existing store closures in the Nix DB so that Nix knows about them at runtime. Use `nix-store --load-db` with the closure info from `pkgs.closureInfo`:
   ```nix
   closureInfoPkg = pkgs.closureInfo { rootPaths = allPackages; };
   ```
   ```bash
   ${nixPackage}/bin/nix-store --load-db < ${closureInfoPkg}/registration
   ```

3. Grant the agent user ownership of the entire `/nix` tree:
   ```bash
   chown -R ${uid}:${uid} ./nix
   ```

### 5. Add `NIX_CONF_DIR` to environment

When `withNix` is true, add to `config.Env`:

```nix
nixEnvVars = lib.optionals withNix [
  "NIX_CONF_DIR=/etc/nix"
];
```

This ensures the Nix CLI picks up the generated `nix.conf`.

### 6. Wire it all together in `mkAgentImage.nix`

The full set of changes to `lib/mkAgentImage.nix`:

- New parameters: `withNix`, `nixPackage`, `nixExperimentalFeatures`
- Conditionally build `nixConf` and `closureInfoPkg`
- Append Nix packages to `allPackages`
- Append Nix store setup to `fakeRootCommands`
- Append `NIX_CONF_DIR` to `config.Env`

No changes needed to `flake.nix` at this stage - predefined images don't enable `withNix`. Users opt in via custom images.

### 7. Add a `withNix` smoke test

Add a second smoke test app in `flake.nix` (`apps.smoke-test-nix`) that:

1. Builds an image with `withNix = true` (e.g. a minimal test image or opencode with Nix enabled)
2. Loads and runs it
3. Verifies:
   ```bash
   nix --version
   nix-shell -p hello --command hello
   ```

This can be a standalone test image defined in the `let` block of the flake outputs, built only for testing and not exported as a package.

### 8. Update the README

Add a `Using Nix Inside Containers` section covering:

- How to enable: `withNix = true` in `mkAgentImage`
- Example custom image definition
- Overriding the Nix version via `nixPackage`
- Customising experimental features via `nixExperimentalFeatures`
- Known limitation: builds inside the container are not sandboxed (`sandbox = false`); users with elevated privileges can override this in their own `nix.conf`
- Host store mount optimisation: document `--mount type=bind,src=/nix/store,dst=/nix/store,ro` for users with Nix on the host

Add a direnv example to the existing Custom Images section:

```nix
extraPackages = [ pkgs.direnv pkgs.nix-direnv ];
```

With a note on shell hook wiring.

### 9. Update CI

Add the `withNix` smoke test to `.github/workflows/ci.yml` as a third job, or extend the existing smoke-test job.

## File change summary

| File | Change |
|---|---|
| `lib/mkAgentImage.nix` | New parameters, conditional Nix setup in packages/fakeRootCommands/env |
| `flake.nix` | Add `smoke-test-nix` app with a test image |
| `README.md` | New section on using Nix inside containers; direnv example |
| `.github/workflows/ci.yml` | Run `withNix` smoke test |

## Open questions

1. **`chown -R` on `/nix/store` at build time**: This could be slow and inflate the image layer. Worth benchmarking. If it's too expensive, an alternative is to make only `/nix/var` and `/nix/store` writable via permissions rather than ownership (e.g. `chmod -R a+w`), though this is less clean.

2. **Store registration**: Need to verify that `nix-store --load-db` works correctly inside `fakeRootCommands` where the store root is `.` rather than `/`. May need to set `NIX_STORE_DIR` or use `--store` flag during the build step.

3. **Image size impact**: Should document the approximate size increase when `withNix` is enabled so users can make an informed choice.
