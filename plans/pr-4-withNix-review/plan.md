# PR #4 review - Implementation plan

See [analysis.md](analysis.md) for full context, approaches, and trade-offs.

## Chosen approaches

- **Comment 1 (default.nix wrapper):** Approach C - no `default.nix`, document `mkAgentImage` as the path for custom builds. No code changes needed.
- **Comment 2 (permission errors):** Approach D only - document `--userns=keep-id` for rootless Podman. No code changes to `mkAgentImage.nix` needed since the errors could not be reproduced.

## Prerequisites (completed)

### Reproduce the permission errors

Tested four scenarios, all passed without errors:

1. `nix build .#nix-test-image` (flake) + `podman run` (rootless).
2. Same with `--userns=keep-id`.
3. Same with `-v ./:/workspace`.
4. `nix build -f . pi --arg withNix true --impure` (0xferrous's `default.nix`) + `podman run`.

**Result:** Permission errors could not be reproduced. The issue is specific to 0xferrous's rootless Podman UID mapping configuration.

---

## Step 1: Document rootless Podman usage (completed)

**File:** `README.md`

Added `--userns=keep-id` workaround to the Known Limitations section under "Using Nix Inside Containers". This avoids a duplicate heading with the existing "NixOS: Rootless Podman Setup" section.

## Step 2: Add `--userns=keep-id` test suite (completed)

**File:** `tests/nix-userns.bats`

Added a Podman-only test file that verifies `/nix/store`, `/tmp`, and `$HOME` writability under `--userns=keep-id`. Tests are skipped when Docker is the runtime.

**File:** `tests/helpers.bash`

Extended `run_in` to accept optional runtime flags before a `--` separator. Existing callers are unaffected since the first argument (image name) does not start with `-`.

**File:** `flake.nix`

Added `test-nix-userns` app entry.

## Step 3: Respond to PR comments (completed)

1. **Comment 1 (default.nix):** Pointed 0xferrous to `lib.mkAgentImage` and the Custom Images README section. Provided a working flake example for their use case (pi with Nix enabled). Explained the `--impure` requirement and maintenance concerns with a `default.nix` wrapper.

2. **Comment 2 (permissions):** Shared reproduction results (four scenarios, all passed). Identified rootless Podman UID remapping as the likely cause. Suggested `--userns=keep-id`, checking `/etc/subuid` and `/etc/subgid`, resetting Podman storage, and sharing `podman info` output. Asked 0xferrous to report back with what resolved the issue.

---

## Files changed

| File                    | Change                                                           |
| ----------------------- | ---------------------------------------------------------------- |
| `README.md`             | Added `--userns=keep-id` to Known Limitations, added test entry. |
| `tests/helpers.bash`    | Extended `run_in` to accept optional runtime flags.              |
| `tests/nix-userns.bats` | New Podman-only test suite for `--userns=keep-id`.               |
| `flake.nix`             | Added `test-nix-userns` app.                                     |
