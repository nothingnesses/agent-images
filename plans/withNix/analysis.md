# `withNix` - First-class Nix workflow support in agent images

Tracking issue: https://github.com/nothingnesses/agent-images/issues/2

## Context

`agent-images` uses Nix to build OCI container images, but using Nix *inside* the resulting containers is not currently supported. For users working in repositories built around `flake.nix`, `shell.nix`, `default.nix`, `devenv`, or NixOS/Home Manager configurations, this creates a gap between how the image is produced and how the agent can work once running.

The proposal is to add an opt-in `withNix = true` flag to `mkAgentImage` that enables Nix workflows inside the container. This keeps default images small while making Nix-heavy workflows available when needed.

### Expected user experience

When enabled, users should be able to run inside the container:

```bash
nix --version
nix flake show
nix develop
nix build
nix shell nixpkgs#hello -c hello
nix-shell -p gh --command "gh issue list -r ..."
```

### Design decisions from issue discussion

- `withNix` should be opt-in, not default - keeps default image sizes minimal.
- `gh` and similar tools should NOT be bundled - users on GitLab, Bitbucket, etc. can add them via `extraPackages`.
- Experimental features (`nix-command`, `flakes`) should be enabled by default inside the container - the container environment can be pragmatic without worrying about upstream stability policy.
- A list of experimental features to enable could be exposed as a parameter, but defaults should cover the common case.

## Issues and approaches

### 1. Writable `/nix/store`

Nix needs a writable `/nix/store` and a populated `/nix/var/nix/db/` at runtime. Container image layers are read-only, with writes going to an overlay. The existing store paths in the image are owned by root from the build process.

#### A) Single-user Nix with store owned by agent user (recommended)

During image build (`fakeRootCommands`), create `/nix/var/nix/` directories, register existing closures in the Nix DB, and grant the agent user write access.

- **Pro**: Self-contained, no host dependency, works across Docker and Podman
- **Con**: `chown` on existing store paths is a large operation at build time; first container write layer may be large

#### B) Mount host `/nix/store` read-only + writable overlay

Document a `--mount` flag that binds the host store in, with a writable upper layer for new paths.

- **Pro**: Efficient - no duplication of store paths already on the host
- **Con**: Couples the container to the host's Nix installation; won't work in CI or environments without Nix on the host; overlay merging is fragile

#### C) Persistent volume for `/nix`

Use a named Docker/Podman volume for the entire `/nix` tree, populated on first run.

- **Pro**: Clean isolation; persists across container restarts so packages aren't re-fetched
- **Con**: First run is slow (everything downloaded from scratch); requires user to manage volume lifecycle

**Decision**: A as the default (self-contained image), with B documented as an optimisation for Nix-on-host users.

---

### 2. Daemon requirements

Nix traditionally uses `nix-daemon` for multi-user setups. In containers, starting a daemon requires root or extra capabilities.

#### A) Single-user mode, no daemon (recommended)

The agent user directly owns and manages the store. No `nix-daemon` process.

- **Pro**: Simple; no init system, no root, no extra capabilities; fits the container model
- **Con**: No isolation between concurrent build processes; store operations aren't mediated by a privileged process

#### B) Start `nix-daemon` via entrypoint wrapper

A small init (e.g., `tini`) starts the daemon as root, then drops to the agent user.

- **Pro**: Multi-user security model; proper build-user isolation
- **Con**: Requires the container to start as root or with `CAP_SYS_ADMIN`; more complex entrypoint; conflicts with the project's non-root-by-default design

**Decision**: A. Single-user mode is the natural fit. The security trade-off (no build-user isolation) is acceptable inside an already-sandboxed container.

---

### 3. Rootless Podman UID namespacing

Rootless Podman uses UID namespacing, which can interfere with Nix's build user UIDs (`nixbld*`).

#### A) Sidestep entirely via single-user mode (recommended)

No `nixbld*` users means no UID mapping issues.

- **Pro**: Problem disappears completely
- **Con**: Depends on choosing single-user mode (see above)

#### B) Pre-create build users with known UIDs

Add `nixbld1`-`nixbld32` to `/etc/passwd` at build time with UIDs that fit within rootless Podman's default subuid range.

- **Pro**: Enables multi-user Nix if ever needed
- **Con**: Fragile - host subuid/subgid configuration varies; breaks if the host maps UIDs differently; maintenance burden

**Decision**: A. Single-user mode makes this a non-issue.

---

### 4. Nix build sandbox

Nix's build sandbox uses Linux namespaces. Inside a container, namespace creation is often restricted, causing sandboxed builds to fail.

#### A) `sandbox = false` in `nix.conf` (recommended)

Disable sandboxing unconditionally.

- **Pro**: Guaranteed to work everywhere - no namespace capabilities needed
- **Con**: Builds aren't hermetic; a build could succeed in the container but fail in a sandboxed environment

#### B) `sandbox = relaxed`

Attempt sandboxing; fall back gracefully.

- **Pro**: Best-effort purity - sandboxed when the runtime allows it
- **Con**: Non-deterministic - same image behaves differently depending on container runtime flags; harder to debug

#### C) Require `--privileged` / `--cap-add SYS_ADMIN`

Document that users must grant the container namespace capabilities.

- **Pro**: Full sandbox support
- **Con**: Major security regression; defeats the purpose of containerisation; many CI environments prohibit this

**Decision**: A as default, with a documented note that users running with elevated privileges can set `sandbox = relaxed` or `sandbox = true` if desired.

---

### 5. Nix version mismatch

The Nix version baked into the image comes from the flake's nixpkgs pin. If a user's project requires a newer Nix, the pinned version may be too old.

#### A) Use nixpkgs-pinned Nix (recommended default)

The Nix CLI version matches whatever nixpkgs the flake locks.

- **Pro**: Zero complexity; reproducible
- **Con**: May lag behind; users whose projects need newer Nix features are stuck

#### B) Separate flake input for Nix (e.g., `github:NixOS/nix`)

Track Nix releases independently of nixpkgs.

- **Pro**: Can stay current without bumping all of nixpkgs
- **Con**: Additional input to maintain; potential incompatibilities between the Nix version and the nixpkgs version used for everything else

#### C) Accept a `nixPackage` parameter (recommended escape hatch)

Let users pass their own Nix derivation to `mkAgentImage`.

- **Pro**: Maximum flexibility; user controls the version
- **Con**: More API surface; user responsibility to ensure compatibility

**Decision**: A as default, with C as an escape hatch. B adds maintenance cost for marginal benefit since the flake's nixpkgs is updated regularly anyway.

---

### 6. `nix develop` / direnv

`nix develop` is the primary workflow for entering Nix-based development environments. Many projects also use `direnv`/`nix-direnv` for automatic shell activation.

#### A) Ensure `nix develop` works out of the box (recommended)

`bashInteractive` is already in `basePackages`. With Nix configured correctly, `nix develop` should just work.

- **Pro**: Core workflow supported with no extra config
- **Con**: `nix develop` spawns a bash subshell, which may interact oddly with some agent entrypoints that expect to control the shell environment

#### B) Include direnv + nix-direnv behind `withNix`

Bundle direnv with shell hooks pre-configured.

- **Pro**: Covers the most common Nix development workflow
- **Con**: Larger image; shell hook setup (`.bashrc` integration) adds complexity; not all users want direnv

#### C) Document direnv as a user-added extra via `extraPackages` (recommended)

Provide a README example showing how to add direnv.

- **Pro**: Keeps `withNix` focused; users opt in to what they need
- **Con**: Shell hook wiring is still non-trivial for users to figure out

**Decision**: A as the baseline. C for direnv - document it as an example in the custom images section rather than bundling it.

### 7. Store ownership at build time

`buildLayeredImage` splits store paths across multiple layers for caching, then runs `fakeRootCommands` to produce a final customisation layer. If `chown -R` is used on `/nix` in `fakeRootCommands`, every store path's metadata must be recorded in the customisation layer, potentially inflating it by hundreds of MB.

#### A) Full `chown -R ./nix` (simple but expensive)

Grant the agent user recursive ownership of the entire `/nix` tree.

- **Pro**: Guaranteed correct for single-user Nix - no ownership ambiguity
- **Con**: Every store path's metadata changes, inflating the customisation layer. Build time scales with store size.

#### B) Shallow ownership (recommended)

Only `chown` the `/nix/store` directory itself (not its contents) and `/nix/var` recursively:

```bash
chown ${uid}:${uid} ./nix ./nix/store
chown -R ${uid}:${uid} ./nix/var
```

Existing store paths are immutable - the agent only needs write access to `/nix/store` (to create new entries) and `/nix/var` (for the DB). Read access to existing paths is sufficient.

- **Pro**: Minimal layer inflation; fast
- **Con**: Nix may check ownership of individual store paths during GC or verification. Assumption needs testing.

#### C) Switch to `buildImage` (single layer) when `withNix` is true

Use `buildImage` instead of `buildLayeredImage` so `chown -R` is baked into one layer with no duplication.

- **Pro**: No layer inflation concern
- **Con**: Loses layer caching - every rebuild re-transfers the entire image

#### D) User-writable alternative store location

Set `NIX_STORE_DIR` to a path under the agent user's home (e.g. `/home/agent/.nix/store`).

- **Pro**: No chown needed at all
- **Con**: Non-standard path; derivations from registries reference `/nix/store`; breaks `nix develop` and flake workflows

**Decision**: B. Shallow ownership is the best default - minimal overhead, correct for the common case. If testing reveals that Nix rejects root-owned paths in single-user mode, fall back to A.

---

### 8. Store registration in `fakeRootCommands`

`fakeRootCommands` runs in a temporary directory where `.` represents the container's filesystem root. `closureInfo` registration files contain absolute `/nix/store/...` paths. `nix-store --load-db` needs to reconcile these two realities.

#### A) Set `NIX_STATE_DIR=$PWD/nix/var/nix`

Redirect the Nix state directory so the DB is written to `./nix/var/nix/db/db.sqlite`. The host's real `/nix/store` contains all referenced paths (they're build inputs), so validation passes.

- **Pro**: One environment variable, one command
- **Con**: `nix-store` may try to acquire locks on or interact with the host's Nix state. Needs testing.

#### B) Generate the SQLite DB as a separate derivation

Write a derivation that takes `closureInfo` output and produces a `db.sqlite`. Include it in the image via `contents` or copy it in `fakeRootCommands`.

- **Pro**: Clean - no interaction with host Nix state during image build. Deterministic and cacheable.
- **Con**: More complex build logic; must replicate the Nix DB schema or invoke `nix-store --load-db` inside the derivation's own sandbox (which has proper `/nix` access).

#### C) First-run entrypoint wrapper

Skip registration at build time. Wrap the entrypoint with a script that runs `nix-store --load-db` on first start (guarded by a flag file).

- **Pro**: Avoids the `fakeRootCommands` path issue entirely
- **Con**: Complicates the entrypoint; slower first container start; conflicts with how orchestrators (agent-box) invoke images

#### D) Register inside a derivation, include the result (recommended)

Build a derivation whose build phase runs `nix-store --init` + `--load-db` in a clean environment, outputting the `/nix/var/nix` tree. Include that derivation in the image's `contents`.

- **Pro**: Correct Nix environment during registration (proper `/nix/store` access). No interaction with host state. Cacheable.
- **Con**: Needs care to ensure the DB references match the actual store paths in the final image. Slightly unusual pattern.

**Decision**: Try A first for simplicity. If `nix-store` interferes with host state or fails under `fakeRootCommands`, use D.

---

### 9. Image size impact

The Nix CLI and its runtime dependencies add to the image size. Users should be able to make an informed choice about enabling `withNix`.

#### A) Benchmark and document a static number

Build with and without `withNix`, note the delta in the README.

- **Pro**: Simple; gives users a quick reference
- **Con**: Goes stale with each nixpkgs bump

#### B) Add size reporting to CI

CI job builds both variants and prints the delta.

- **Pro**: Always current; catches unexpected bloat from dependency changes
- **Con**: Extra CI time and complexity

#### C) Both (recommended)

CI tracks the actual number. README gives a ballpark (e.g. "~X MB overhead, varies by nixpkgs pin").

- **Pro**: Best of both - quick reference in docs, accurate number in CI
- **Con**: Minor maintenance to keep the README number reasonably current

**Decision**: C. Document an approximate number in the README and add CI size reporting to keep it honest.

## Summary

The recurring theme is that **single-user Nix with `sandbox = false`** resolves the majority of issues simultaneously (daemon, rootless Podman, sandbox, UID mapping). The main engineering work is in properly setting up the store, DB, and permissions at image build time. The rest is mostly configuration and documentation.

### Implementation scope

1. Add `withNix` (default `false`) parameter to `mkAgentImage`
2. When enabled:
   - Include the Nix CLI and runtime dependencies in the image
   - Configure single-user Nix (`sandbox = false`, experimental features enabled)
   - Set up `/nix/var/nix/` directories with correct ownership
   - Register existing store closures in the Nix DB
3. Optionally accept a `nixPackage` parameter for version override
4. Optionally accept a `nixExperimentalFeatures` list (defaulting to `["nix-command" "flakes"]`)
5. Document the feature in the README, including:
   - How to enable it
   - Host store mount optimisation
   - direnv as an `extraPackages` example
   - Known limitations
6. Add a smoke test verifying basic Nix operations inside a `withNix` image
