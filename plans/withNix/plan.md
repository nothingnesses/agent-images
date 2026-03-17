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
| Store ownership | Shallow `chown` (directory-level, not recursive into store paths) |
| Store registration | `NIX_STATE_DIR` redirect in `fakeRootCommands`; fall back to derivation-based DB |
| Image size | Benchmark in CI + approximate number in README |

## Steps

### 1. Validate assumptions

Several decisions rest on assumptions that must be tested before committing to the approach. Build a minimal test image and verify each assumption in a container.

#### 1a. Shallow ownership works with single-user Nix

The plan uses shallow `chown` (only `/nix/store` directory + `/nix/var` recursive) instead of `chown -R` on the entire store. This assumes single-user Nix can operate on root-owned store paths it didn't create.

**Test**: Build a test image with shallow ownership. Inside the container, run:

```bash
# Existing paths are readable
nix path-info /nix/store/* 2>&1 | head -5

# New paths can be created
nix build --no-link nixpkgs#hello

# GC can remove paths
nix store gc --max 0
```

**Pass criteria**: All commands succeed without permission errors.

**Fallback**: If any fail, switch to full `chown -R ./nix` (analysis section 7, option A) and re-measure image size impact.

#### 1b. `NIX_STATE_DIR` redirect works in `fakeRootCommands`

The plan uses `NIX_STATE_DIR=$PWD/nix/var/nix` to write the DB to the container's filesystem during `fakeRootCommands`. This assumes `nix-store --load-db` doesn't interfere with the host's Nix state.

**Test**: Build the image. If the build succeeds, verify inside the container:

```bash
# DB exists and is queryable
nix path-info --all | wc -l

# Count matches the number of store paths in the image
ls /nix/store | wc -l
```

**Pass criteria**: Build completes without errors. Path count from `nix path-info --all` roughly matches the number of store paths.

**Fallback**: If `nix-store` interferes with host state or fails, switch to a derivation that builds the DB in isolation (analysis section 8, option D).

#### 1c. `nix develop` works out of the box

`bashInteractive` is in `basePackages`, but `nix develop` may have additional runtime expectations.

**Test**: Mount a directory containing a minimal `flake.nix` with a `devShell` into the container and run:

```bash
cd /workspace
nix develop --command echo "devshell works"
```

**Pass criteria**: Command prints "devshell works" and exits 0.

### 2. Add new parameters to `mkAgentImage`

In `lib/mkAgentImage.nix`, add to the function signature:

```nix
withNix ? false,
nixPackage ? pkgs.nix,
nixExperimentalFeatures ? [ "nix-command" "flakes" ],
```

### 3. Build the Nix configuration file

When `withNix` is true, create a `nix.conf` derivation:

```nix
nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
  sandbox = false
  experimental-features = ${lib.concatStringsSep " " nixExperimentalFeatures}
'';
```

### 4. Include Nix packages conditionally

Add the Nix CLI and its runtime dependencies to `allPackages` when `withNix` is true:

```nix
nixPackages = lib.optionals withNix [ nixPackage nixConf ];
allPackages = [ agent ] ++ basePackages ++ extraPackages ++ nixPackages;
```

`nixPackage` (default `pkgs.nix`) provides both `nix` and legacy commands (`nix-shell`, `nix-build`, etc.).

### 5. Set up Nix store and DB in `fakeRootCommands`

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

2. Register the image's existing store closures in the Nix DB. Use `NIX_STATE_DIR` to redirect the DB to the container's filesystem:
   ```nix
   closureInfoPkg = pkgs.closureInfo { rootPaths = allPackages; };
   ```
   ```bash
   NIX_STATE_DIR=$PWD/nix/var/nix ${nixPackage}/bin/nix-store --load-db < ${closureInfoPkg}/registration
   ```

3. Shallow ownership - grant the agent user write access to `/nix/store` (directory) and `/nix/var` (recursive), without recursing into store path contents:
   ```bash
   chown ${uid}:${uid} ./nix ./nix/store
   chown -R ${uid}:${uid} ./nix/var
   ```

### 6. Add `NIX_CONF_DIR` to environment

When `withNix` is true, add to `config.Env`:

```nix
nixEnvVars = lib.optionals withNix [
  "NIX_CONF_DIR=/etc/nix"
];
```

This ensures the Nix CLI picks up the generated `nix.conf`.

### 7. Wire it all together in `mkAgentImage.nix`

The full set of changes to `lib/mkAgentImage.nix`:

- New parameters: `withNix`, `nixPackage`, `nixExperimentalFeatures`
- Conditionally build `nixConf` and `closureInfoPkg`
- Append Nix packages to `allPackages`
- Append Nix store setup to `fakeRootCommands`
- Append `NIX_CONF_DIR` to `config.Env`

No changes needed to `flake.nix` at this stage - predefined images don't enable `withNix`. Users opt in via custom images.

### 8. Add smoke tests

Add two test apps in `flake.nix`:

#### `apps.smoke-test-nix` - basic Nix functionality

Define a test image in the `let` block with `withNix = true` (e.g. opencode + Nix, or a minimal agent). The test:

1. Builds the test image
2. Loads it into podman/docker
3. Verifies basic operations:
   ```bash
   nix --version
   nix path-info --all | wc -l   # DB is populated
   ```

#### `apps.smoke-test-nix-install` - runtime package installation

Uses the same test image to verify that Nix can fetch and run packages at runtime:

```bash
nix-shell -p hello --command hello
```

This is a separate test because it requires network access and is slower. It validates the full single-user Nix workflow end-to-end.

#### Test for shallow ownership assumption

Include in `smoke-test-nix`:

```bash
# Verify store directory is writable by agent
touch /nix/store/.write-test && rm /nix/store/.write-test

# Verify existing store paths are readable
nix path-info $(which nix)
```

#### Test for `nix develop`

Include in `smoke-test-nix-install` (requires network):

```bash
# Create a minimal flake and test nix develop
mkdir -p /tmp/test-flake
cat > /tmp/test-flake/flake.nix <<'FLAKE'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs = { nixpkgs, ... }:
    let pkgs = import nixpkgs { system = builtins.currentSystem; };
    in { devShells.${builtins.currentSystem}.default = pkgs.mkShell { buildInputs = [ pkgs.hello ]; }; };
}
FLAKE
cd /tmp/test-flake
nix develop --command hello
```

### 9. Update the README

Add a `Using Nix Inside Containers` section covering:

- How to enable: `withNix = true` in `mkAgentImage`
- Example custom image definition
- Overriding the Nix version via `nixPackage`
- Customising experimental features via `nixExperimentalFeatures`
- Known limitation: builds inside the container are not sandboxed (`sandbox = false`); users with elevated privileges can override this in their own `nix.conf`
- Host store mount optimisation: document `--mount type=bind,src=/nix/store,dst=/nix/store,ro` for users with Nix on the host
- Approximate image size overhead (from benchmarking in step 1)

Add a direnv example to the existing Custom Images section:

```nix
extraPackages = [ pkgs.direnv pkgs.nix-direnv ];
```

With a note on shell hook wiring.

### 10. Update CI

In `.github/workflows/ci.yml`:

1. Add a `smoke-test-nix` job that runs `nix run .#smoke-test-nix`
2. Add a size reporting step that builds an image with and without `withNix`, compares tarball sizes, and prints the delta. This runs alongside the smoke test, not as a gate.

## File change summary

| File | Change |
|---|---|
| `lib/mkAgentImage.nix` | New parameters, conditional Nix setup in packages/fakeRootCommands/env |
| `flake.nix` | Add `smoke-test-nix` and `smoke-test-nix-install` apps with a test image |
| `README.md` | New section on using Nix inside containers; direnv example; size note |
| `.github/workflows/ci.yml` | Run `withNix` smoke test; add size reporting step |
