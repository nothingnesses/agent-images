# agent-images

Sandboxed OCI container images for AI coding agents, built reproducibly with Nix.

Consumes agent packages from [llm-agents.nix](https://github.com/numtide/llm-agents.nix) and produces images usable with [agent-box](https://github.com/0xferrous/agent-box) or standalone Podman/Docker.

```
llm-agents.nix (packages)  ->  agent-images (images)  ->  agent-box (orchestration)
```

## Why

AI coding agents need access to your filesystem to be useful, but that means
they can also read secrets like SSH keys, cloud credentials, and API tokens.
Running agents inside containers limits what they can see. Nix makes the images
reproducible and easy to customise.

## Available Images

#### AI Coding Agents

| Image | Agent | Build |
|-------|-------|-------|
| `amp` | [Amp](https://ampcode.com/) | `nix build .#amp` |
| `claude-code` | [Claude Code](https://claude.ai/code) | `nix build .#claude-code` |
| `cli-proxy-api` | [CLI Proxy API](https://github.com/router-for-me/CLIProxyAPI) | `nix build .#cli-proxy-api` |
| `code` | [Code](https://github.com/just-every/code/) | `nix build .#code` |
| `codex` | [Codex CLI](https://github.com/openai/codex) | `nix build .#codex` |
| `copilot-cli` | [Copilot CLI](https://github.com/github/copilot-cli) | `nix build .#copilot-cli` |
| `crush` | [Crush](https://github.com/charmbracelet/crush) | `nix build .#crush` |
| `cursor-agent` | [Cursor Agent](https://cursor.com/) | `nix build .#cursor-agent` |
| `droid` | [Droid](https://factory.ai) | `nix build .#droid` |
| `eca` | [ECA](https://github.com/editor-code-assistant/eca) | `nix build .#eca` |
| `forge` | [Forge](https://github.com/antinomyhq/forge) | `nix build .#forge` |
| `gemini-cli` | [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `nix build .#gemini-cli` |
| `goose-cli` | [Goose](https://github.com/block/goose) | `nix build .#goose-cli` |
| `iflow-cli` | [iFlow CLI](https://github.com/iflow-ai/iflow-cli) | `nix build .#iflow-cli` |
| `jules` | [Jules](https://jules.google) | `nix build .#jules` |
| `kilocode-cli` | [Kilocode CLI](https://kilocode.ai/cli) | `nix build .#kilocode-cli` |
| `letta-code` | [Letta Code](https://github.com/letta-ai/letta-code) | `nix build .#letta-code` |
| `mistral-vibe` | [Mistral Vibe](https://github.com/mistralai/mistral-vibe) | `nix build .#mistral-vibe` |
| `nanocoder` | [Nanocoder](https://github.com/Mote-Software/nanocoder) | `nix build .#nanocoder` |
| `oh-my-opencode` | [Oh My OpenCode](https://github.com/code-yeongyu/oh-my-openagent) | `nix build .#oh-my-opencode` |
| `omp` | [OMP](https://github.com/can1357/oh-my-pi) | `nix build .#omp` |
| `opencode` | [OpenCode](https://github.com/anomalyco/opencode) | `nix build .#opencode` |
| `pi` | [Pi](https://github.com/badlogic/pi-mono) | `nix build .#pi` |
| `qoder-cli` | [Qoder CLI](https://qoder.com) | `nix build .#qoder-cli` |
| `qwen-code` | [Qwen Code](https://github.com/QwenLM/qwen-code) | `nix build .#qwen-code` |

#### AI Assistants

| Image | Agent | Build |
|-------|-------|-------|
| `hermes-agent` | [Hermes Agent](https://hermes-agent.nousresearch.com/) | `nix build .#hermes-agent` |
| `localgpt` | [LocalGPT](https://github.com/localgpt-app/localgpt) | `nix build .#localgpt` |
| `openclaw` | [OpenClaw](https://openclaw.ai) | `nix build .#openclaw` |
| `picoclaw` | [PicoClaw](https://picoclaw.io) | `nix build .#picoclaw` |
| `zeroclaw` | [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) | `nix build .#zeroclaw` |

Each image includes a default set of base packages: git, coreutils, bash, ripgrep, findutils, grep, sed, gawk, diff, jq, tar, gzip, less, curl, which, and CA certificates. These can be overridden via the `basePackages` parameter (see [Custom Images](#custom-images)). By default, containers run as a non-root `agent` user (uid 1000) with `/workspace` as the working directory. Both the user and working directory can be customised (see [Custom Images](#custom-images)).

## Requirements

- [Nix](https://nixos.org/) with [flakes enabled](https://wiki.nixos.org/wiki/Flakes)
- [Podman](https://podman.io/) or [Docker](https://www.docker.com/) for loading and running images

All other dependencies (including agent packages from [llm-agents.nix](https://github.com/numtide/llm-agents.nix)) are resolved automatically by the Nix flake. NixOS users should also follow the [rootless Podman setup](#nixos-rootless-podman-setup) steps below.

## Quick Start

```bash
# List all available images with descriptions
nix search . ^

# Replace <agent> with any image name from the table above
nix build .#<agent>
podman load < result  # or: docker load < result
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

### Smoke Test

To run the build, load, and verification steps automatically:

```bash
nix run .#smoke-test           # defaults to opencode
nix run .#smoke-test -- codex  # or specify any agent
```

## Usage with agent-box

### Global Configuration

Create `~/.agent-box.toml`:

```toml
workspace_dir = "~/.local/agent-box/workspaces"
base_repo_dir = "~/path/to/your/projects"

[runtime]
backend = "podman"
# Replace <agent> with any image name from the table above
image = "localhost/agent-images/<agent>:latest"
env_passthrough = ["ANTHROPIC_API_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY"]
```

`base_repo_dir` must be the real (non-symlinked) parent directory containing your git repositories. Agent-box resolves symlinks, so symlinking repos into a separate directory will not work. Add any other API keys your agent requires to `env_passthrough`.

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
# Check agent version
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
# Replace <agent> with any image name from the table above
nix build .#<agent>

# Local mode - agent CAN see result
ab spawn --local --entrypoint ls -c="-la" -c="result"
# Output: result -> /nix/store/...

# Worktree mode - agent CANNOT see result
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

### Troubleshooting

**Corrupted storage after failed load.** If `podman load` fails (e.g. because `/etc/subuid` was missing), Podman's storage may be corrupted. Fix with:

```bash
podman system reset --force
podman load < result
```

**`newuidmap: Too many levels of symbolic links`.** This happens when `/etc/subuid` is a symlink (e.g. from `environment.etc` entries). NixOS setuid wrappers cannot follow symlinks. Remove any `environment.etc` entries for `subuid`/`subgid` and rely solely on `subUidRanges`/`subGidRanges`, which create real files. Rebuild and then reset Podman storage.

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

### Overriding Base Packages

By default, images include a standard set of CLI tools (bash, coreutils, git, etc.). Pass `basePackages` to replace them entirely:

```nix
mkAgentImage {
  name = "my-minimal-agent";
  agent = my-agent-package;
  entrypoint = [ "my-agent" ];
  basePackages = with pkgs; [ bashInteractive coreutils git cacert ];
}
```

### Customising User and Working Directory

By default, containers run as user `agent` (uid 1000) with `/workspace` as the working directory. Override these with `user`, `uid`, and `workingDir`:

```nix
mkAgentImage {
  name = "my-agent";
  agent = my-agent-package;
  entrypoint = [ "my-agent" ];
  user = "dev";
  uid = 1001;
  workingDir = "/project";
}
```

## Using Nix Inside Containers

By default, the Nix CLI is not included in images. Set `withNix = true` to enable Nix workflows inside the container:

```nix
mkAgentImage {
  name = "my-agent";
  agent = my-agent-package;
  entrypoint = [ "my-agent" ];
  withNix = true;
};
```

This configures single-user Nix with `nix-command` and `flakes` experimental features enabled. Inside the container, you can run:

```bash
nix --version
nix develop
nix build
nix shell nixpkgs#hello -c hello
nix-shell -p ripgrep --command "rg --version"
```

### Overriding the Nix Version

The Nix CLI version defaults to whatever the flake's nixpkgs pins. Pass `nixPackage` to use a different version:

```nix
mkAgentImage {
  name = "my-agent";
  agent = my-agent-package;
  entrypoint = [ "my-agent" ];
  withNix = true;
  nixPackage = my-custom-nix;
};
```

### Customising Experimental Features

The default experimental features are `nix-command` and `flakes`. Override with `nixExperimentalFeatures`:

```nix
mkAgentImage {
  name = "my-agent";
  agent = my-agent-package;
  entrypoint = [ "my-agent" ];
  withNix = true;
  nixExperimentalFeatures = [ "nix-command" "flakes" "pipe-operators" ];
};
```

### Adding direnv

direnv is not included by default but can be added via `extraPackages`:

```nix
mkAgentImage {
  name = "my-agent";
  agent = my-agent-package;
  entrypoint = [ "my-agent" ];
  withNix = true;
  extraPackages = [ pkgs.direnv pkgs.nix-direnv ];
};
```

You will also need to wire up the shell hook. Add an `extraEnv` entry or configure `.bashrc` in the container's home directory to run `eval "$(direnv hook bash)"`.

### Known Limitations

- **No build sandbox**: Nix builds inside the container run with `sandbox = false` because container runtimes typically restrict namespace creation. Builds are not hermetic - a derivation that succeeds in the container may fail in a sandboxed environment. If your container runs with elevated privileges, you can override this by mounting a custom `nix.conf` with `sandbox = relaxed` or `sandbox = true`.
- **Image size**: Enabling `withNix` adds the Nix CLI and its dependencies to the image. Expect roughly 50-150 MB of additional size depending on the nixpkgs pin.

### Host Store Mount Optimisation

If the host machine has Nix installed, you can bind-mount the host store read-only to avoid duplicating store paths:

```bash
podman run --rm -it \
  --mount type=bind,src=/nix/store,dst=/nix/store,ro \
  -v ./my-project:/workspace \
  localhost/agent-images/my-agent:latest
```

This is useful for reducing disk usage but couples the container to the host's Nix installation.

### Smoke Tests

```bash
nix run .#smoke-test-nix           # basic Nix checks (offline)
nix run .#smoke-test-nix-install   # runtime install + nix develop (requires network)
nix run .#smoke-test-nix-custom    # custom user/uid, experimental features, extraEnv (with Nix)
nix run .#smoke-test-custom        # custom user/uid/workingDir, extraPackages, extraEnv (without Nix)
```

## License

This project is licensed under the [Blue Oak Model License 1.0.0](LICENSE).
