{
  description = "OCI container images for AI coding agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
    flake-utils.url = "github:numtide/flake-utils";
    agent-box = {
      url = "github:0xferrous/agent-box";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, llm-agents, flake-utils, agent-box }:
    {
      lib.mkAgentImage = { pkgs, lib ? pkgs.lib }:
        import ./lib/mkAgentImage.nix { inherit pkgs lib; };
    }
    //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        lib = pkgs.lib;
        agents = llm-agents.packages.${system};

        mkAgentImage = import ./lib/mkAgentImage.nix { inherit pkgs lib; };

        ab = pkgs.rustPlatform.buildRustPackage {
          pname = "ab";
          version = "0.1.0";
          src = agent-box;
          cargoLock.lockFile = "${agent-box}/Cargo.lock";
          cargoBuildFlags = [ "-p" "ab" ];
          cargoTestFlags = [ "-p" "ab" ];
        };

        agentConfigs = {
          # AI Coding Agents
          amp = {};
          claude-code = {};
          cli-proxy-api = {};
          code = {};
          codex = {};
          copilot-cli = {};
          crush = {};
          cursor-agent = {};
          droid = {};
          eca = {};
          forge = {};
          gemini-cli = {};
          goose-cli = {};
          iflow-cli = {};
          jules = {};
          kilocode-cli = {};
          letta-code = {};
          mistral-vibe = {};
          nanocoder = {};
          oh-my-opencode = {};
          omp = {};
          opencode = {};
          pi = {};
          qoder-cli = {};
          qwen-code = {};
          # AI Assistants
          hermes-agent = {};
          localgpt = {};
          openclaw = {};
          picoclaw = {};
          zeroclaw = {};
        };
      in
      {
        packages = lib.mapAttrs (name: cfg:
          let agent = agents.${cfg.agentPkg or name};
          in mkAgentImage {
            name = "agent-images/${name}";
            inherit agent;
            entrypoint = [ agent.meta.mainProgram ];
            extraPackages = cfg.extraPackages or [];
            extraEnv = cfg.extraEnv or {};
          }
        ) agentConfigs;

        devShells.default = pkgs.mkShell {
          packages = [ ab ];
        };

        apps.smoke-test = let
          script = pkgs.writeShellScript "smoke-test" ''
            set -euo pipefail

            agent="''${1:-opencode}"
            image="localhost/agent-images/$agent:latest"

            if command -v podman &>/dev/null; then
              runtime=podman
            elif command -v docker &>/dev/null; then
              runtime=docker
            else
              echo "ERROR: neither podman nor docker found"
              exit 1
            fi

            echo "==> Building $agent"
            nix build ".#$agent"

            echo "==> Loading image ($runtime)"
            $runtime load < result

            echo "==> Checking --version"
            $runtime run --rm "$image" --version

            echo "==> Verifying container internals"
            output=$($runtime run --rm --entrypoint sh "$image" -c \
              'whoami && echo $HOME && pwd && command -v git && command -v rg')

            user=$(echo "$output" | sed -n '1p')
            home=$(echo "$output" | sed -n '2p')
            workdir=$(echo "$output" | sed -n '3p')

            fail=0
            [ "$user" = "agent" ]      || { echo "FAIL: user is '$user', expected 'agent'"; fail=1; }
            [ "$home" = "/home/agent" ] || { echo "FAIL: HOME is '$home', expected '/home/agent'"; fail=1; }
            [ "$workdir" = "/workspace" ] || { echo "FAIL: workdir is '$workdir', expected '/workspace'"; fail=1; }

            if [ "$fail" -eq 0 ]; then
              echo "==> All checks passed for $agent"
            else
              exit 1
            fi
          '';
        in {
          type = "app";
          program = "${script}";
        };
      }
    );
}
