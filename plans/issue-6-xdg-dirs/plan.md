# XDG base directories and `extraDirectories` implementation plan

Tracking issue: https://github.com/nothingnesses/agent-images/issues/6

## Problem

When users bind-mount a subdirectory of an XDG path (e.g. `~/.config/git`) into the container, the container runtime implicitly creates the missing parent directory as `root:root`. Since the container runs as a non-root user, the parent becomes unwritable, breaking tools that expect to write elsewhere under that tree.

## Solution

Two coordinated changes to `mkAgentImage`:

1. Pre-create the four standard XDG base directories, owned by the container user, and set the corresponding env vars.
2. Add an `extraDirectories` list parameter for arbitrary additional directories.

XDG paths are hardcoded from `home` rather than exposed as a dedicated parameter. Users who need non-standard XDG paths can combine `extraDirectories` (to create the directory) with `extraEnv` (to set the env var), which is explicit and consistent with the existing API.

## New parameter

### `extraDirectories`

A list of directory paths, either absolute or using `~/` to refer to the container user's home. Each path is normalized (expanding `~/` to `$HOME`), then `mkdir -p`'d and `chown`'d to the container user. Using `~/` decouples callers from knowledge of the container user's home path.

```nix
extraDirectories ? [],
```

Paths are normalized before validation:

```nix
normalizeOwnedDirectory = dir:
  if dir == "~" then home
  else if lib.hasPrefix "~/" dir then "${home}/${lib.removePrefix "~/" dir}"
  else dir;
```

Validated with `lib.assertMsg` assertions (run against normalized paths). `lib.assertMsg` is used instead of bare `assert` because it wraps failures in `throw`, which `builtins.tryEval` reliably catches, enabling eval-time assertion tests in `nix flake check`. Bare `assert` failures are not guaranteed to be caught by `builtins.tryEval` across Nix versions.

```nix
# Every normalized path must be absolute.
assert lib.assertMsg (lib.all (d: lib.hasPrefix "/" d) (map normalizeOwnedDirectory extraDirectories))
  "mkAgentImage: extraDirectories entries must be absolute container paths or use ~/...";

# Reject system paths that should never be chowned to the container user.
deniedPrefixes = [ "/etc" "/bin" "/usr" "/lib" "/sbin" "/dev" "/proc" "/sys" "/run" "/tmp" "/nix" "/var" "/root" ];
assert lib.assertMsg (lib.all (d: !(lib.any (p: d == p || lib.hasPrefix (p + "/") d) deniedPrefixes)) (map normalizeOwnedDirectory extraDirectories))
  "mkAgentImage: extraDirectories must not include system paths (${lib.concatStringsSep ", " deniedPrefixes})";

# Reject paths containing whitespace or shell metacharacters.
assert lib.assertMsg (lib.all (d: builtins.match "[a-zA-Z0-9/_.+@-]+" d != null) (map normalizeOwnedDirectory extraDirectories))
  "mkAgentImage: extraDirectories paths may only contain alphanumeric characters, /, _, ., +, @, and -";

# Reject paths containing ".." components to prevent deny-list bypass (e.g. /nix/../etc).
assert lib.assertMsg (lib.all (d: builtins.match ".*\\.\\." d == null) (map normalizeOwnedDirectory extraDirectories))
  "mkAgentImage: extraDirectories paths must not contain '..' components";
```

The deny-list prevents accidental chowning of system directories (e.g. `/etc`, `/nix`, `/var`) which would break the container. The `..` rejection prevents bypassing the deny-list via path traversal (e.g. `/nix/../etc` would match neither `/nix` nor `/etc` in a prefix check). The character-set assertion is a readability/sanity check; `lib.escapeShellArg` handles the actual shell safety when paths are interpolated into `fakeRootCommands`. The set includes `+` and `@` since these are valid in directory names. Paths that fail these assertions produce a build-time error with a descriptive message.

Only the listed path itself is chowned, not its implicitly-created parents. For example, if a user passes `/opt/data/cache`, `mkdir -p` creates `/opt` and `/opt/data` as root-owned; only `/opt/data/cache` is chowned to the container user. Users who need writable intermediates should include them explicitly in the list. Paths under `$HOME` do not have this limitation because `defaultOwnedDirectories` explicitly lists every intermediate (e.g. `.local` for `.local/share` and `.local/state`).

## Excluded XDG variables

`XDG_RUNTIME_DIR` is excluded. It is managed by `pam_systemd`, requires a tmpfs with strict lifecycle semantics, and cannot be meaningfully pre-created in a container image.

`XDG_DATA_DIRS` and `XDG_CONFIG_DIRS` are excluded. They are system-level search paths (like `PATH`), not user-owned directories, and are unaffected by the mount-ownership issue.

## Implementation details

### `lib/mkAgentImage.nix`

#### Parameter list

Add after `extraEnv`:

```nix
extraDirectories ? [],
```

#### Internal resolution (in the inner `let` block)

```nix
normalizeOwnedDirectory = dir:
  if dir == "~" then home
  else if lib.hasPrefix "~/" dir then "${home}/${lib.removePrefix "~/" dir}"
  else dir;

defaultOwnedDirectories = [
  home
  "${home}/.config"
  "${home}/.cache"
  "${home}/.local"
  "${home}/.local/share"
  "${home}/.local/state"
  workingDir
];

ownedDirectories = lib.unique (
  defaultOwnedDirectories ++ map normalizeOwnedDirectory extraDirectories
);

ownedDirectoryArgs = lib.concatMapStringsSep " "
  (dir: lib.escapeShellArg ".${dir}") ownedDirectories;

xdgEnvPairs = {
  XDG_CONFIG_HOME = "${home}/.config";
  XDG_CACHE_HOME = "${home}/.cache";
  XDG_DATA_HOME = "${home}/.local/share";
  XDG_STATE_HOME = "${home}/.local/state";
};

# Filter out any XDG vars that the user overrides via extraEnv,
# avoiding duplicate env var names (undefined behavior per OCI spec).
xdgEnvVars = lib.mapAttrsToList (k: v: "${k}=${v}")
  (lib.filterAttrs (k: _: !(lib.hasAttr k extraEnv)) xdgEnvPairs);
```

`home` and `workingDir` are included in `defaultOwnedDirectories` so that all ownership is managed in one place. Every intermediate directory that `mkdir -p` would implicitly create (e.g., `.local` for `.local/share`) is listed explicitly, so a flat (non-recursive) `chown` covers everything without risking silent re-ownership of unexpected files.

#### Assertions

Add `deniedPrefixes` in the inner `let` block:

```nix
deniedPrefixes = [ "/etc" "/bin" "/usr" "/lib" "/sbin" "/dev" "/proc" "/sys" "/run" "/tmp" "/nix" "/var" "/root" ];
```

Add before the `pkgs.dockerTools.buildLayeredImage` call. All assertions run against `ownedDirectories` (i.e., after normalization), so `~/` paths are resolved before validation. Use `lib.assertMsg` (not bare `assert`) so that `builtins.tryEval` can reliably catch failures in the eval-time assertion tests:

```nix
assert lib.assertMsg (lib.all (d: lib.hasPrefix "/" d) ownedDirectories)
  "mkAgentImage: extraDirectories entries must be absolute container paths or use ~/...";
assert lib.assertMsg (lib.all (d: !(lib.any (p: d == p || lib.hasPrefix (p + "/") d) deniedPrefixes)) ownedDirectories)
  "mkAgentImage: extraDirectories must not include system paths (${lib.concatStringsSep ", " deniedPrefixes})";
assert lib.assertMsg (lib.all (d: builtins.match "[a-zA-Z0-9/_.+@-]+" d != null) ownedDirectories)
  "mkAgentImage: extraDirectories paths may only contain alphanumeric characters, /, _, ., +, @, and -";
assert lib.assertMsg (lib.all (d: builtins.match ".*\\.\\." d == null) ownedDirectories)
  "mkAgentImage: extraDirectories paths must not contain '..' components";
```

#### `fakeRootCommands`

Currently:

```bash
mkdir -p ./etc .${home} ./tmp .${workingDir}
# ...
chown ${uidStr}:${gidStr} .${home} .${workingDir}
```

Changes to:

```bash
mkdir -p ./etc ./tmp ${ownedDirectoryArgs}
# ...
chown ${uidStr}:${gidStr} ${ownedDirectoryArgs}
```

Paths are escaped with `lib.escapeShellArg` as defense in depth (the assertion already rejects problematic characters at eval time). All directories, including `$HOME`, `workingDir`, XDG dirs, and `extraDirectories`, are chowned individually (non-recursive). This is safe because every intermediate that `mkdir -p` would implicitly create (e.g., `.local`) is explicitly listed in `defaultOwnedDirectories`.

Note that `mkdir -p` may create intermediate parent directories as root-owned for `extraDirectories` entries outside `$HOME`. Only the listed paths are chowned (see `extraDirectories` parameter docs above).

#### `config.Env`

Add `xdgEnvVars` to the env list, between the base vars and `nixEnvVars`:

```nix
Env = [
  "HOME=${home}"
  "USER=${user}"
  "PATH=${lib.makeBinPath allPackages}"
  "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
]
++ xdgEnvVars
++ nixEnvVars
++ (lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv);
```

### `flake.nix`

#### Extend existing `customTestImage`

Rather than creating dedicated test images, extend the existing `customTestImage` to also exercise `extraDirectories` and XDG env var overriding. This avoids an additional image build in CI while testing the interaction between custom user settings (`uid`, `gid`, `home`, `workingDir`) and directory ownership.

Add `XDG_CONFIG_HOME` to `extraEnv` (alongside the existing `CUSTOM_VAR`) and add `extraDirectories`:

```nix
customTestImage = mkAgentImage {
  name = "agent-images/custom-test";
  agent = agents.opencode;
  entrypoint = [ agents.opencode.meta.mainProgram ];
  user = "dev";
  uid = 1002;
  gid = 100;
  workingDir = "/project";
  extraPackages = [ pkgs.hello ];
  extraEnv = {
    CUSTOM_VAR = "custom-value";
    XDG_CONFIG_HOME = "/home/dev/.custom-config";
  };
  extraDirectories = [
    "~"
    "~/.dev-cache"
    "~/.custom-config"
    "~/.my+app@v2"
    "/opt/dev-cache"
  ];
};
```

- `~` tests bare tilde normalization (resolves to `$HOME`).
- `~/.dev-cache` tests `~/` normalization with a custom home.
- `~/.custom-config` corresponds to the overridden `XDG_CONFIG_HOME`.
- `~/.my+app@v2` tests that paths with allowed special characters (`+`, `@`) are accepted.
- `/opt/dev-cache` tests an absolute path outside `$HOME` (uses `/opt` rather than `/var` because `/var` is on the deny-list).

### `tests/helpers.bash`

Fix the `run_in` flag parsing. The current loop breaks on arguments that don't start with `-`, which means multi-word flags like `--tmpfs /path` stop parsing prematurely (the path doesn't start with `-`, so the loop exits and the value argument becomes the image name).

Change the while-loop condition from:

```bash
while [[ $# -gt 0 && $1 == -* ]]; do
```

to:

```bash
while [[ $# -gt 0 && $1 != "--" ]]; do
```

This collects everything before `--` as flags, regardless of whether individual arguments start with `-`. The `--` sentinel then cleanly separates flags from the image and command.

**Breaking change:** the new loop requires `--` to know where flags end. Existing callers that pass no flags (e.g. `run_in "${IMAGE}" whoami`) will break because the image name would be consumed as a flag. All existing `run_in` calls must be updated to include `--` before the image argument. This is a mechanical change: `run_in "${IMAGE}" ...` becomes `run_in -- "${IMAGE}" ...`.

#### Existing `run_in` call migration

Update every `run_in` call in existing test files to insert `--` before the image argument:

- `tests/default.bats`: all `run_in "${IMAGE}" ...` calls become `run_in -- "${IMAGE}" ...`.
- `tests/custom.bats`: same.
- `tests/nix.bats`: same.
- `tests/nix-custom.bats`: same.
- `tests/nix-install.bats`: same.
- `tests/nix-userns.bats`: same.

### `tests/default.bats`

Add tests for default XDG behavior. The default image uses the standard user/home, so these verify the baseline.

```
@test "XDG env vars are set to defaults"
  - XDG_CONFIG_HOME equals /home/agent/.config
  - XDG_CACHE_HOME equals /home/agent/.cache
  - XDG_DATA_HOME equals /home/agent/.local/share
  - XDG_STATE_HOME equals /home/agent/.local/state

@test "XDG base directories exist and are writable"
  - touch a file in each of: .config, .cache, .local/share, .local/state

@test "subpath mount does not break parent writability"
  - use `run_in --tmpfs /home/agent/.config/test-subdir:rw -- "${IMAGE}"` to mount a tmpfs at a subpath
  - verify ~/.config itself is still writable by touching a file there
  - note: uses tmpfs rather than a bind mount for simplicity; the key property under test
    is that the pre-created parent survives a child mount, which tmpfs exercises equally
```

### `tests/custom.bats`

Add tests for XDG behavior with a custom user, XDG override via `extraEnv`, and `extraDirectories`. The custom image exercises all three features together.

```
@test "default XDG base directories exist for custom user"
  - touch a file in each of: .config, .cache, .local/share, .local/state
  - verifies XDG dirs follow the custom home (/home/dev), not the default (/home/agent)

@test "XDG_CONFIG_HOME is overridden by extraEnv"
  - env var equals /home/dev/.custom-config (not the default /home/dev/.config)

@test "overridden XDG_CONFIG_HOME directory exists and is writable"
  - touch a file in /home/dev/.custom-config

@test "XDG_CACHE_HOME retains default when not overridden"
  - env var equals /home/dev/.cache

@test "XDG_DATA_HOME retains default when not overridden"
  - env var equals /home/dev/.local/share

@test "XDG_STATE_HOME retains default when not overridden"
  - env var equals /home/dev/.local/state

@test "no duplicate XDG_CONFIG_HOME in env"
  - run `env | grep -c '^XDG_CONFIG_HOME='` and assert count is 1
  - note: anchor with ^ and = to avoid false matches from other env vars
    whose values happen to contain the string XDG_CONFIG_HOME

@test "extraDirectories are created and owned by the runtime user"
  - check $HOME/.dev-cache exists with ownership 1002:100
  - check /opt/dev-cache exists with ownership 1002:100

@test "extraDirectories with special characters exist"
  - check $HOME/.my+app@v2 exists with ownership 1002:100
  - verifies paths containing +, @ are accepted by the character-set assertion

@test "tilde normalization resolves to custom home"
  - stat /home/dev/.dev-cache (full absolute path, not via $HOME)
  - verifies ~/  expanded against the custom home, not the default /home/agent

@test "extraDirectories intermediate parents outside HOME remain root-owned"
  - stat -c '%u:%g' /opt and assert it equals 0:0
  - confirms that only the listed path (/opt/dev-cache) is chowned,
    not the implicitly-created parent (/opt)
```

### `flake.nix` (assertion tests)

Add Nix-level checks that verify eval-time assertions reject invalid `extraDirectories` inputs. Each check uses `builtins.tryEval` at eval time to confirm the assertion fires, then gates a trivial `runCommand` derivation on the result. Add these to the `checks` output alongside `pre-commit-check`.

`builtins.tryEval` catches the `lib.assertMsg` failure at eval time (since `lib.assertMsg` wraps the failure in `throw`, which `tryEval` reliably catches). The outer `assert !result.success` fails `nix flake check` if a regression removes an assertion, because `tryEval` would succeed where it should not.

```nix
assertionChecks = let
  assertRejects = name: dirs:
    let
      result = builtins.tryEval (mkAgentImage {
        name = "assert-test";
        agent = agents.opencode;
        entrypoint = [ agents.opencode.meta.mainProgram ];
        extraDirectories = dirs;
      });
    in
    assert !result.success;
    pkgs.runCommand "assert-rejects-${name}" {} "touch $out";
in {
  assert-rejects-relative-path = assertRejects "relative-path" [ "relative/path" ];
  assert-rejects-denied-prefix-etc = assertRejects "denied-prefix-etc" [ "/etc/shadow" ];
  assert-rejects-denied-prefix-var = assertRejects "denied-prefix-var" [ "/var/data" ];
  assert-rejects-dotdot-traversal = assertRejects "dotdot-traversal" [ "/nix/../etc" ];
  assert-rejects-whitespace = assertRejects "whitespace" [ "/foo bar" ];
  assert-rejects-bare-denied = assertRejects "bare-denied" [ "/etc" ];
};
```

### `README.md`

Add a section documenting:

- XDG base directories are pre-created by default.
- How to use `extraDirectories` for additional directories, including `~/` syntax for paths relative to the container user's home.
- That only the listed paths are chowned; intermediate parents created by `mkdir -p` for paths outside `$HOME` remain root-owned. Users who need writable intermediates should list them explicitly.
- How to combine `extraDirectories` + `extraEnv` for non-standard XDG paths.
- That `XDG_RUNTIME_DIR` is intentionally excluded and why.
- That `extraDirectories` rejects system paths (`/etc`, `/bin`, `/usr`, `/lib`, `/sbin`, `/dev`, `/proc`, `/sys`, `/run`, `/tmp`, `/nix`, `/var`, `/root`) and paths containing `..` at build time, and only accepts paths composed of alphanumeric characters, `/`, `_`, `.`, `+`, `@`, and `-`.

## File change summary

| File                     | Change                                                                                                                                                                                                                                                                                                                                               |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/mkAgentImage.nix`   | Add `extraDirectories` parameter with `~/` normalization and assertions (absolute paths, deny-list, `..` rejection, safe characters); hardcode XDG dirs in `defaultOwnedDirectories`; create and flat-chown dirs in `fakeRootCommands` with `lib.escapeShellArg`; set env vars with `extraEnv` dedup.                                                |
| `flake.nix`              | Extend `customTestImage` with `extraDirectories` (including bare `~` and special-character paths) and `XDG_CONFIG_HOME` override in `extraEnv`. Add eval-time assertion checks using `builtins.tryEval` that verify invalid `extraDirectories` inputs (relative paths, denied prefixes, `..` traversal, whitespace, bare denied paths) are rejected. |
| `tests/helpers.bash`     | Fix `run_in` flag parsing to collect all args before `--` as flags, not just args starting with `-`.                                                                                                                                                                                                                                                 |
| `tests/default.bats`     | Add XDG env var, directory writability, and subpath mount tests; migrate `run_in` calls to use `--` separator.                                                                                                                                                                                                                                       |
| `tests/custom.bats`      | Add XDG override (all four vars), no-duplicate-env-var, extraDirectories ownership, special-character path, tilde normalization, intermediate parent ownership, and custom-user XDG tests; migrate `run_in` calls to use `--` separator.                                                                                                             |
| `tests/nix.bats`         | Migrate `run_in` calls to use `--` separator.                                                                                                                                                                                                                                                                                                        |
| `tests/nix-custom.bats`  | Migrate `run_in` calls to use `--` separator.                                                                                                                                                                                                                                                                                                        |
| `tests/nix-install.bats` | Migrate `run_in` calls to use `--` separator.                                                                                                                                                                                                                                                                                                        |
| `tests/nix-userns.bats`  | Migrate `run_in` calls to use `--` separator.                                                                                                                                                                                                                                                                                                        |
| `README.md`              | Document XDG and extraDirectories features.                                                                                                                                                                                                                                                                                                          |

## Backward compatibility

- `extraDirectories` defaults to `[]`, preserving current behavior apart from the addition of XDG env vars and directories (which is the fix).
- Existing images gain XDG dirs and env vars automatically, which is the desired outcome. No user action needed.
- `extraEnv` can override XDG env vars because of how `lib.mapAttrsToList` and the `Env` list are constructed: `xdgEnvVars` appears before `extraEnv` in the concatenation. However, the OCI spec does not define behavior for duplicate env var names in the `Env` list, and runtime behavior varies (some use last-wins, some reject duplicates). To avoid relying on undefined behavior, `xdgEnvVars` should be filtered to exclude any keys that appear in `extraEnv`. This keeps the override path explicit and portable.
