{
  description = "Sandboxed OCI container images for AI coding agents";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

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

        # Test image for withNix smoke tests (not exported as a package)
        nixTestImage = mkAgentImage {
          name = "agent-images/nix-test";
          agent = agents.opencode;
          entrypoint = [ agents.opencode.meta.mainProgram ];
          withNix = true;
        };
      in
      {
        packages = (lib.mapAttrs (name: cfg:
          let agent = agents.${cfg.agentPkg or name};
          in mkAgentImage {
            name = "agent-images/${name}";
            inherit agent;
            entrypoint = [ agent.meta.mainProgram ];
            extraPackages = cfg.extraPackages or [];
            extraEnv = cfg.extraEnv or {};
          }
        ) agentConfigs) // {
          nix-test-image = nixTestImage;
        };

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

        apps.smoke-test-nix = let
          script = pkgs.writeShellScript "smoke-test-nix" ''
            set -euo pipefail

            image="localhost/agent-images/nix-test:latest"

            if command -v podman &>/dev/null; then
              runtime=podman
            elif command -v docker &>/dev/null; then
              runtime=docker
            else
              echo "ERROR: neither podman nor docker found"
              exit 1
            fi

            echo "==> Building nix-test image"
            nix build ".#nix-test-image"

            echo "==> Loading image ($runtime)"
            $runtime load < result

            echo "==> Verifying nix is available"
            $runtime run --rm --entrypoint sh "$image" -c 'nix --version'

            echo "==> Verifying store DB is populated"
            count=$($runtime run --rm --entrypoint sh "$image" -c 'nix path-info --all | wc -l')
            echo "    $count store paths registered"
            [ "$count" -gt 0 ] || { echo "FAIL: no store paths registered"; exit 1; }

            echo "==> Verifying shallow ownership (store dir writable)"
            $runtime run --rm --entrypoint sh "$image" -c \
              'touch /nix/store/.write-test && rm /nix/store/.write-test'

            echo "==> Verifying store path query works"
            path=$($runtime run --rm --entrypoint sh "$image" -c 'nix path-info --all | head -1')
            $runtime run --rm --entrypoint sh "$image" -c "nix path-info $path"

            echo "==> All nix checks passed"
          '';
        in {
          type = "app";
          program = "${script}";
        };

        apps.smoke-test-nix-install = let
          script = pkgs.writeShellScript "smoke-test-nix-install" ''
            set -euo pipefail

            image="localhost/agent-images/nix-test:latest"

            if command -v podman &>/dev/null; then
              runtime=podman
            elif command -v docker &>/dev/null; then
              runtime=docker
            else
              echo "ERROR: neither podman nor docker found"
              exit 1
            fi

            # Assume image is already loaded (run smoke-test-nix first)
            echo "==> Testing runtime package installation"
            $runtime run --rm --entrypoint sh "$image" -c \
              'nix-shell -p hello --command hello'

            echo "==> Testing nix develop"
            $runtime run --rm --entrypoint sh "$image" -c '
              mkdir -p /tmp/test-flake
              cat > /tmp/test-flake/flake.nix <<FLAKE
            {
              inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
              outputs = { nixpkgs, ... }:
                let pkgs = import nixpkgs { system = "${system}"; };
                in { devShells.${system}.default = pkgs.mkShell { buildInputs = [ pkgs.hello ]; }; };
            }
            FLAKE
              cd /tmp/test-flake
              nix develop --command hello
            '

            echo "==> All nix-install checks passed"
          '';
        in {
          type = "app";
          program = "${script}";
        };
      }
    );
}
