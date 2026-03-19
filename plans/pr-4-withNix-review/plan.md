# PR #4 review - Implementation plan

See [analysis.md](analysis.md) for full context, approaches, and trade-offs.

## Chosen approaches

- **Comment 1 (default.nix wrapper):** Approach C - no `default.nix`, document `mkAgentImage` as the path for custom builds. No code changes needed.
- **Comment 2 (permission errors):** Approach C + D - fix store/tmp/home ownership in the image build, and document `--userns=keep-id` for rootless Podman.

## Prerequisites

### Reproduce the permission errors

Before changing code, confirm the root cause by reproducing 0xferrous's errors locally.

1. Build a `withNix` image:
   ```bash
   nix build .#nix-test-image
   ```
2. Load and run with Podman (rootless):
   ```bash
   podman load < result
   podman run --rm -ti --entrypoint sh localhost/agent-images/nix-test:latest
   ```
3. Inside the container, test:
   ```bash
   touch /nix/store/.write-test          # test store writability
   mkdir /tmp/test-dir                    # test /tmp writability
   mkdir -p ~/.test-dir                   # test home writability
   nix shell nixpkgs#hello -c hello      # test runtime install
   nix-shell -p hello --command hello     # test nix-shell
   ```
4. If errors reproduce, also test with `--userns=keep-id`:
   ```bash
   podman run --rm -ti --userns=keep-id --entrypoint sh localhost/agent-images/nix-test:latest
   ```
   If this resolves all errors, the root cause is confirmed as UID remapping.

The results of reproduction determine which steps below are needed.

---

## Step 1: Add `auto-optimise-store = false` to `nix.conf`

**File:** `lib/mkAgentImage.nix`

The `.links` directory error occurs because Nix tries to create `/nix/store/.links` for hard-link deduplication. Disabling this avoids the error regardless of store ownership.

Change the `nixConf` definition (line 44-47) from:

```nix
nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
  sandbox = false
  experimental-features = ${lib.concatStringsSep " " nixExperimentalFeatures}
'';
```

to:

```nix
nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
  sandbox = false
  auto-optimise-store = false
  experimental-features = ${lib.concatStringsSep " " nixExperimentalFeatures}
'';
```

## Step 2: Ensure `/nix/store` ownership in the customisation layer

**File:** `lib/mkAgentImage.nix`

The `fakeRootCommands` customisation layer sits on top of the content layers in the final image. Creating `./nix/store` in `fakeRootCommands` and chowning it should override the root-owned directory entry from the content layers, since the overlay filesystem resolves directory metadata from the uppermost layer.

Change the `nixFakeRootCommands` definition (line 58-60) from:

```nix
nixFakeRootCommands = lib.optionalString withNix ''
  chown -R ${uidStr}:${uidStr} ./nix
'';
```

to:

```nix
nixFakeRootCommands = lib.optionalString withNix ''
  mkdir -p ./nix/store
  chown -R ${uidStr}:${uidStr} ./nix
'';
```

The `mkdir -p ./nix/store` ensures the store directory exists in the customisation layer so `chown -R ./nix` covers it. Without this, `./nix` only contains `./nix/var` (from `includeNixDB`), and `/nix/store` is only present in the content layers.

**Verification needed:** After building, confirm inside the container that `ls -ld /nix/store` shows ownership as the agent user, not root.

## Step 3: Update tests

**File:** `tests/nix.bats`

Add a test to verify `/nix/store` ownership:

```bash
@test "nix store is owned by agent user" {
  run run_in "${IMAGE}" 'stat -c %U /nix/store'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "agent" ]]
}
```

Update the existing `nix-custom.bats` to verify store ownership matches the custom user as well.

## Step 4: Document rootless Podman usage

**File:** `README.md`

Add a section under the usage documentation covering rootless Podman. The key points:

- Rootless Podman uses UID namespace remapping by default, which can cause permission issues with pre-built image ownership.
- Recommend `--userns=keep-id` to map the host user's UID directly into the container:
  ```bash
  podman run --rm -ti --userns=keep-id -v ./:/workspace localhost/agent-images/pi:latest
  ```
- This is only needed for rootless Podman. Docker and rootful Podman do not have this issue.

## Step 5: Respond to PR comments

After implementing and verifying:

1. **Comment 1 (default.nix):** Thank 0xferrous for the suggestion. Explain that the project exposes `lib.mkAgentImage` for custom builds and that this is the intended path for parameterised image construction. A `default.nix` wrapper would require `--impure` and create a second entry point to maintain. Point to the README's custom image example.

2. **Comment 2 (permissions):** Explain the fixes made (store ownership, `auto-optimise-store = false`). If rootless Podman was confirmed as a factor, note the `--userns=keep-id` documentation. Ask 0xferrous to re-test with the updated branch.

---

## Files changed

| File | Change |
|------|--------|
| `lib/mkAgentImage.nix` | Add `auto-optimise-store = false` to `nix.conf`; add `mkdir -p ./nix/store` before `chown` |
| `tests/nix.bats` | Add store ownership test |
| `tests/nix-custom.bats` | Add store ownership test for custom user |
| `README.md` | Document rootless Podman `--userns=keep-id` usage |
