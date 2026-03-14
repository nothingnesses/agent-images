# Standalone Usage (Podman/Docker)

## Build and load an image

```bash
# Build the Claude Code image
nix build github:user/agent-images#claude-code

# Load into Podman
podman load < result

# Or load into Docker
docker load < result
```

## Run interactively

```bash
podman run --rm -it \
  -v ./project:/workspace \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  agent-images/claude-code:latest
```

## Check the version

```bash
podman run --rm agent-images/claude-code:latest --version
```

## Other agents

```bash
# Codex
nix build .#codex && podman load < result
podman run --rm -it -v ./project:/workspace -e OPENAI_API_KEY="$OPENAI_API_KEY" agent-images/codex:latest

# Gemini CLI
nix build .#gemini && podman load < result
podman run --rm -it -v ./project:/workspace -e GEMINI_API_KEY="$GEMINI_API_KEY" agent-images/gemini:latest

# OpenCode
nix build .#opencode && podman load < result
podman run --rm -it -v ./project:/workspace agent-images/opencode:latest
```

## Verify container internals

```bash
podman run --rm agent-images/claude-code:latest sh -c '
  whoami &&
  echo $HOME &&
  pwd &&
  which git &&
  which rg
'
# Expected: agent, /home/agent, /workspace, /nix/store/.../bin/git, /nix/store/.../bin/rg
```
