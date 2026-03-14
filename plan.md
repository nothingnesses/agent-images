# Plan: agent-images.nix

## Context

AI coding agents (Claude Code, Codex, Gemini CLI, etc.) can be run in containers for sandboxing, but no tool provides **ready-to-use OCI images** with these agents pre-installed. The ecosystem has:

- **llm-agents.nix** (numtide): Nix packages for agent binaries — but not container images
- **agent-box**: Container orchestration (workspaces, mounts, profiles) — but requires users to bring their own image
- **Docker Sandboxes**: Pre-configured agent images — but Docker Desktop-proprietary

This project fills the gap: a Nix flake that consumes llm-agents.nix packages and produces OCI images via `dockerTools.buildLayeredImage`, usable with agent-box or standalone.

```
llm-agents.nix (packages)  →  agent-images.nix (images)  →  agent-box (orchestration)
```

## Scope

### In Scope
- OCI images for AI coding agents, built reproducibly via Nix
- Base development tools in every image (git, coreutils, bash, ripgrep, etc.)
- Proper container setup (non-root user, home dir, /tmp, /etc/passwd, locale)
- Loadable by Podman and Docker
- Usable with agent-box or standalone `podman run`

### Out of Scope
- Sandbox orchestration (agent-box handles this)
- Mount-stacking / file exclusion (agent-box + git worktrees handle this)
- Network filtering
- Portal / mediated host access

## Architecture

```nix
# flake.nix inputs
{
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  llm-agents.url = "github:numtide/llm-agents.nix";
  flake-utils.url = "github:numtide/flake-utils";
}
```

### Image Structure

Each image contains:

```
/bin/, /usr/bin/      ← base tools (git, bash, ripgrep, etc.)
/etc/passwd           ← agent user (uid 1000)
/etc/group            ← agent group (gid 1000)
/etc/nsswitch.conf    ← name resolution
/home/agent/          ← home directory
/tmp/                 ← writable temp
/workspace/           ← mount point for project
<agent binary>        ← claude, codex, gemini, etc.
```

### Core Nix Function

```nix
mkAgentImage = {
  name,           # image name (e.g., "agent-images/claude-code")
  tag ? "latest", # image tag
  agent,          # agent package from llm-agents.nix
  entrypoint,     # e.g., [ "claude" ]
  extraPackages ? [],
  extraEnv ? {},
}: pkgs.dockerTools.buildLayeredImage {
  inherit name tag;
  contents = [
    agent
    basePackages    # git, coreutils, bash, ripgrep, findutils, gnugrep, gawk, less, curl, cacert
  ] ++ extraPackages;

  # Custom /etc/passwd, /etc/group, /etc/nsswitch.conf, home dir, tmp
  fakeRootCommands = ''
    mkdir -p ./home/agent ./tmp ./workspace
    echo "root:x:0:0:root:/root:/bin/bash" > ./etc/passwd
    echo "agent:x:1000:1000:agent:/home/agent:/bin/bash" >> ./etc/passwd
    echo "root:x:0:" > ./etc/group
    echo "agent:x:1000:" >> ./etc/group
    echo "hosts: files dns" > ./etc/nsswitch.conf
    chown 1000:1000 ./home/agent ./workspace
  '';

  config = {
    User = "agent";
    WorkingDir = "/workspace";
    Entrypoint = entrypoint;
    Env = [
      "HOME=/home/agent"
      "USER=agent"
      "PATH=/bin:/usr/bin"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ] ++ (lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv);
  };
};
```

## Implementation

### File Structure

```
agent-images/
├── flake.nix          # Inputs, outputs, per-system image packages
├── flake.lock
├── lib/
│   └── mkAgentImage.nix   # Core image builder function
├── agents/
│   ├── claude-code.nix    # Claude Code image definition
│   ├── codex.nix          # Codex CLI image definition
│   ├── gemini.nix         # Gemini CLI image definition
│   └── opencode.nix       # OpenCode image definition
└── examples/
    ├── standalone.md      # Usage with plain podman run
    └── agent-box.md       # Usage with agent-box
```

### Step 1: Flake skeleton + mkAgentImage

Create `flake.nix` with inputs (nixpkgs, llm-agents, flake-utils) and the `mkAgentImage` function in `lib/mkAgentImage.nix`.

Verify with a minimal test image that `nix build` produces a loadable tarball and `podman load < result` works.

**Files**: `flake.nix`, `lib/mkAgentImage.nix`

### Step 2: Claude Code image

First real agent image. Define in `agents/claude-code.nix`:

```nix
{ mkAgentImage, llm-agents, pkgs }:
mkAgentImage {
  name = "agent-images/claude-code";
  agent = llm-agents.packages.${pkgs.system}.claude-code;
  entrypoint = [ "claude" ];
  extraPackages = with pkgs; [ nodejs ];  # Claude Code needs Node.js
}
```

Build, load, test: `podman run --rm -it agent-images/claude-code:latest --version`

**Files**: `agents/claude-code.nix`

### Step 3: Additional agents

Add Codex, Gemini CLI, OpenCode. Each is a small Nix file specifying the package, entrypoint, and any extra dependencies.

**Files**: `agents/codex.nix`, `agents/gemini.nix`, `agents/opencode.nix`

### Step 4: Flake outputs

Expose:
- `packages.${system}.claude-code` — Claude Code OCI image tarball
- `packages.${system}.codex` — Codex CLI image tarball
- `packages.${system}.gemini` — Gemini CLI image tarball
- `packages.${system}.opencode` — OpenCode image tarball
- `lib.mkAgentImage` — for consumers to build custom agent images

**Files**: `flake.nix` (updated)

### Step 5: Usage examples

Document two workflows:

**Standalone** (plain podman):
```bash
nix build github:user/agent-images#claude-code
podman load < result
podman run --rm -it -v ./project:/workspace agent-images/claude-code:latest
```

**With agent-box**:
```toml
# ~/.agent-box.toml
[runtime]
image = "agent-images/claude-code:latest"
```
```bash
nix build github:user/agent-images#claude-code && podman load < result
ab new myrepo -s session
ab spawn -r myrepo -s session
```

**Files**: `examples/standalone.md`, `examples/agent-box.md`

## Verification

### Build test
```bash
nix build .#claude-code
# Should produce: result → /nix/store/...-docker-image-agent-images-claude-code.tar.gz
```

### Load + basic test
```bash
podman load < result
podman run --rm agent-images/claude-code:latest --version
# Should print Claude Code version
```

### Interactive test
```bash
podman run --rm -it \
  -v ./test-project:/workspace \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  agent-images/claude-code:latest
# Should drop into Claude Code session
```

### Verify container internals
```bash
podman run --rm agent-images/claude-code:latest sh -c '
  whoami &&             # should be "agent"
  echo $HOME &&         # should be "/home/agent"
  pwd &&                # should be "/workspace"
  which git &&          # should find git
  which ripgrep || which rg  # should find rg
'
```

### Test with agent-box
```bash
# Set image in ~/.agent-box.toml, then:
ab spawn --local
# Should drop into container with agent ready
```

## Open Questions to Resolve During Implementation

1. **llm-agents.nix package availability**: Verify which agents are actually packaged. Check `nix flake show github:numtide/llm-agents.nix` for the current list.

2. **Claude Code Node.js dependency**: Claude Code is a Node.js app. Verify whether the llm-agents.nix package bundles Node.js or if we need to add it as an extra package.

3. **Image size**: Build the Claude Code image and check its size. If it's excessively large (>1GB), consider optimization (minimal base, layer caching).

4. **`fakeRootCommands` vs `runAsRoot`**: `fakeRootCommands` uses `fakeroot` (no real root needed) while `runAsRoot` uses actual root in a VM. Try `fakeRootCommands` first; fall back to `runAsRoot` if `chown` doesn't work.

5. **`config.User` support**: Verify that `dockerTools.buildLayeredImage` respects the `User` field. If not, set `USER=agent` in env and let the entrypoint handle it.

6. **PATH construction**: The Nix store paths for binaries need to be in `$PATH`. `dockerTools` handles this via wrapper scripts or `symlinkJoin`, but verify the exact mechanism.
