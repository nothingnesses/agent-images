# agent-images

OCI container images for AI coding agents, built reproducibly with Nix.

Consumes agent packages from [llm-agents.nix](https://github.com/numtide/llm-agents.nix) and produces images usable with [agent-box](https://github.com/0xferrous/agent-box) or standalone Podman/Docker.

```
llm-agents.nix (packages)  →  agent-images (images)  →  agent-box (orchestration)
```

## Available Images

| Image | Agent | Build |
|-------|-------|-------|
| `claude-code` | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `nix build .#claude-code` |
| `codex` | [Codex CLI](https://github.com/openai/codex) | `nix build .#codex` |
| `gemini` | [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `nix build .#gemini` |
| `opencode` | [OpenCode](https://github.com/opencode-ai/opencode) | `nix build .#opencode` |
| `pi` | [pi](https://github.com/mariozechner/pi) | `nix build .#pi` |

Each image includes: git, coreutils, bash, ripgrep, findutils, grep, sed, gawk, diff, jq, less, curl, and CA certificates. Containers run as a non-root `agent` user (uid 1000) with `/workspace` as the working directory.

## Quick Start

```bash
# Replace <agent> with one of: claude-code, codex, gemini, opencode, pi
nix build .#<agent>
podman load < result
podman run --rm localhost/agent-images/<agent>:latest --version
```

### Standalone Usage

Pass the API key for your chosen provider:

```bash
# Claude Code (Anthropic)
podman run --rm -it \
  -v ./my-project:/workspace \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  localhost/agent-images/claude-code:latest

# OpenCode (OpenRouter)
podman run --rm -it \
  -v ./my-project:/workspace \
  -e OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  localhost/agent-images/opencode:latest
```

### Verifying Container Internals

```bash
# Replace <agent> with the image name used above
podman run --rm --entrypoint sh localhost/agent-images/<agent>:latest \
  -c 'whoami && echo $HOME && pwd && command -v git && command -v rg'
```

Expected output:
```
agent
/home/agent
/workspace
/nix/store/.../bin/git
/nix/store/.../bin/rg
```

## Usage with agent-box

### Global Configuration

Create `~/.agent-box.toml`:

```toml
workspace_dir = "~/.local/agent-box/workspaces"
base_repo_dir = "~/path/to/your/projects"

[runtime]
backend = "podman"
# Replace <agent> with one of: claude-code, codex, gemini, opencode, pi
image = "localhost/agent-images/<agent>:latest"
env_passthrough = ["ANTHROPIC_API_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY"]
```

`base_repo_dir` must be the real (non-symlinked) parent directory containing your git repositories. Agent-box resolves symlinks, so symlinking repos into a separate directory will not work. Add the API key environment variables for whichever providers you use.

### Local Mode

Mounts the current directory as-is into the container. The agent can see all files, including untracked and gitignored files.

```bash
cd ~/projects/my-repo
ab spawn --local
```

### Worktree Mode (Sandboxed)

Creates a git worktree so the agent only sees committed/tracked files. Gitignored files (like `result`) are not visible.

```bash
# Create a workspace (from within the repo directory)
ab new my-repo -s my-session --git

# Spawn the container
ab spawn -s my-session --git
```

### Running One-Off Commands

Use `--entrypoint` to override the default entrypoint and `-c` for arguments:

```bash
# Check agent version (replace <entrypoint> with: claude, codex, gemini, opencode)
ab spawn --local --entrypoint <entrypoint> -c="--version"

# Read a file
ab spawn --local --entrypoint cat -c="README.md"

# Run a shell command (note: pass each arg as a separate -c)
ab spawn --local --entrypoint sh -c="-c" -c="whoami && pwd"
```

### Sandbox Verification

To verify that worktree mode hides gitignored files:

```bash
# Build an image first (creates a `result` symlink, which is gitignored)
# Replace <agent> with one of: claude-code, codex, gemini, opencode, pi
nix build .#<agent>

# Local mode — agent CAN see result
ab spawn --local --entrypoint ls -c="-la" -c="result"
# Output: result -> /nix/store/...

# Worktree mode — agent CANNOT see result
ab new my-repo -s sandbox-test --git
ab spawn -s sandbox-test --git --entrypoint ls -c="result"
# Output: ls: cannot access 'result': No such file or directory
```

## NixOS: Rootless Podman Setup

NixOS requires extra configuration for rootless Podman to work with these images. Add the following to your `configuration.nix`:

```nix
virtualisation = {
  containers.enable = true;
  podman = {
    enable = true;
    dockerCompat = true;
  };
};

users.users.<USERNAME> = {
  extraGroups = [ "podman" ];
  subUidRanges = [{ startUid = 100000; count = 65536; }];
  subGidRanges = [{ startGid = 100000; count = 65536; }];
};

# The subUidRanges/subGidRanges options above do not reliably generate
# /etc/subuid and /etc/subgid. These environment.etc entries ensure the
# files exist. Without them, Podman cannot map container UIDs and images
# with non-root users will fail to load.
environment.etc = {
  "subuid".text = "<USERNAME>:100000:65536";
  "subgid".text = "<USERNAME>:100000:65536";
};
```

Then rebuild: `sudo nixos-rebuild switch`

**Note:** The `sudo` commands and `podman load`/`podman system reset` commands below must be run from your own terminal. Sandboxed environments (such as AI coding agents running inside containers) cannot execute `sudo` or access `/etc/subuid` due to the "no new privileges" flag.

You also need a container trust policy. Create `~/.config/containers/policy.json`:

```json
{
  "default": [
    { "type": "insecureAcceptAnything" }
  ]
}
```

### Corrupted Storage Recovery

If you load an image while `/etc/subuid` is missing, Podman's storage gets corrupted (layers unpacked with wrong UID mappings). Fix with:

```bash
podman system reset --force
# Ensure /etc/subuid and /etc/subgid exist, then reload
podman load < result
```

## Custom Images

Use `mkAgentImage` to build your own agent images:

```nix
{
  inputs.agent-images.url = "github:nothingnesses/agent-images";

  outputs = { agent-images, nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      mkAgentImage = agent-images.lib.mkAgentImage { inherit pkgs; };
    in {
      packages.x86_64-linux.my-agent = mkAgentImage {
        name = "my-agent";
        agent = my-agent-package;
        entrypoint = [ "my-agent" ];
        extraPackages = [ pkgs.nodejs ];
        extraEnv = { MY_VAR = "value"; };
      };
    };
}
```

## License

This project is licensed under the [Blue Oak Model License 1.0.0](LICENSE).
