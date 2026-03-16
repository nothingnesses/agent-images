# Usage with agent-box

## Setup

Build and load the image:

```bash
# Replace <agent> with one of: claude-code, codex, gemini, opencode
nix build .#<agent>
podman load < result
```

Configure agent-box to use it:

```toml
# ~/.agent-box.toml
[runtime]
# Replace <agent> with one of: claude-code, codex, gemini, opencode
image = "agent-images/<agent>:latest"
backend = "podman"
```

## Run

```bash
# Create a workspace and spawn the agent
ab new myrepo -s session
ab spawn -r myrepo -s session
```

## Multiple agents via profiles

```toml
# ~/.agent-box.toml
[runtime]
image = "agent-images/claude-code:latest"
backend = "podman"

[profiles.codex]
[profiles.codex.runtime]
image = "agent-images/codex:latest"

[profiles.gemini]
[profiles.gemini.runtime]
image = "agent-images/gemini:latest"
```

```bash
# Use the codex profile
ab spawn -r myrepo -s session -p codex
```
