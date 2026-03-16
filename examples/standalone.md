# Standalone Usage (Podman/Docker)

## Build and load an image

```bash
# Replace <agent> with any image name (see README for full list)
nix build .#<agent>

# Load into Podman
podman load < result

# Or load into Docker
docker load < result
```

## Run interactively

```bash
# Replace <agent> and set the appropriate API key env var for your provider
podman run --rm -it \
  -v ./project:/workspace \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  agent-images/<agent>:latest
```

## Check the version

```bash
podman run --rm agent-images/<agent>:latest --version
```

## Verify container internals

```bash
podman run --rm --entrypoint sh agent-images/<agent>:latest -c '
  whoami &&
  echo $HOME &&
  pwd &&
  command -v git &&
  command -v rg
'
# Expected: agent, /home/agent, /workspace, /nix/store/.../bin/git, /nix/store/.../bin/rg
```
