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

        # Test image for custom user/uid, experimental features, and extraEnv
        nixTestImageCustom = mkAgentImage {
          name = "agent-images/nix-test-custom";
          agent = agents.opencode;
          entrypoint = [ agents.opencode.meta.mainProgram ];
          withNix = true;
          user = "ci";
          uid = 1001;
          nixExperimentalFeatures = [ "nix-command" "flakes" "pipe-operators" ];
          extraEnv = { MY_VAR = "test-value"; };
        };

        # Test image for non-nix customizations (custom user/uid/workingDir, extraPackages, extraEnv)
        customTestImage = mkAgentImage {
          name = "agent-images/custom-test";
          agent = agents.opencode;
          entrypoint = [ agents.opencode.meta.mainProgram ];
          user = "dev";
          uid = 1002;
          workingDir = "/project";
          extraPackages = [ pkgs.hello ];
          extraEnv = { CUSTOM_VAR = "custom-value"; };
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
          nix-test-image-custom = nixTestImageCustom;
          custom-test-image = customTestImage;
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

            echo "==> Verifying nix is NOT available (withNix defaults to false)"
            if $runtime run --rm --entrypoint sh "$image" -c 'command -v nix' 2>/dev/null; then
              echo "FAIL: nix should not be present in default image"
              fail=1
            fi

            echo "==> Verifying /tmp is writable"
            if ! $runtime run --rm --entrypoint sh "$image" -c 'touch /tmp/test-file && rm /tmp/test-file'; then
              echo "FAIL: /tmp is not writable"
              fail=1
            fi

            echo "==> Verifying HOME is writable"
            if ! $runtime run --rm --entrypoint sh "$image" -c 'touch $HOME/test-file && rm $HOME/test-file'; then
              echo "FAIL: HOME directory is not writable"
              fail=1
            fi

            echo "==> Verifying SSL_CERT_FILE is set and exists"
            if ! $runtime run --rm --entrypoint sh "$image" -c '[ -n "$SSL_CERT_FILE" ] && [ -f "$SSL_CERT_FILE" ]'; then
              echo "FAIL: SSL_CERT_FILE is not set or file does not exist"
              fail=1
            fi

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

            echo "==> Verifying nix.conf content"
            conf=$($runtime run --rm --entrypoint sh "$image" -c 'cat /etc/nix/nix.conf')
            echo "$conf" | grep -q 'sandbox = false' || { echo "FAIL: nix.conf missing 'sandbox = false'"; exit 1; }
            echo "$conf" | grep -q 'experimental-features = nix-command flakes' || { echo "FAIL: nix.conf missing expected experimental features"; exit 1; }

            echo "==> Verifying NIX_CONF_DIR and NIX_PATH environment variables"
            $runtime run --rm --entrypoint sh "$image" -c '
              [ "$NIX_CONF_DIR" = "/etc/nix" ] || { echo "FAIL: NIX_CONF_DIR=$NIX_CONF_DIR, expected /etc/nix"; exit 1; }
              [ -n "$NIX_PATH" ] || { echo "FAIL: NIX_PATH is empty"; exit 1; }
              echo "    NIX_CONF_DIR=$NIX_CONF_DIR"
              echo "    NIX_PATH=$NIX_PATH"
            '

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

        apps.smoke-test-nix-custom = let
          script = pkgs.writeShellScript "smoke-test-nix-custom" ''
            set -euo pipefail

            image="localhost/agent-images/nix-test-custom:latest"

            if command -v podman &>/dev/null; then
              runtime=podman
            elif command -v docker &>/dev/null; then
              runtime=docker
            else
              echo "ERROR: neither podman nor docker found"
              exit 1
            fi

            echo "==> Building nix-test-custom image"
            nix build ".#nix-test-image-custom"

            echo "==> Loading image ($runtime)"
            $runtime load < result

            echo "==> Verifying custom user and uid (case 2)"
            output=$($runtime run --rm --entrypoint sh "$image" -c 'whoami && id -u')
            user=$(echo "$output" | sed -n '1p')
            uid_val=$(echo "$output" | sed -n '2p')
            [ "$user" = "ci" ] || { echo "FAIL: user is '$user', expected 'ci'"; exit 1; }
            [ "$uid_val" = "1001" ] || { echo "FAIL: uid is '$uid_val', expected '1001'"; exit 1; }

            echo "==> Verifying nix works with custom user"
            $runtime run --rm --entrypoint sh "$image" -c 'nix --version'

            echo "==> Verifying /nix ownership matches custom uid"
            $runtime run --rm --entrypoint sh "$image" -c \
              'touch /nix/store/.write-test && rm /nix/store/.write-test'
            owner=$($runtime run --rm --entrypoint sh "$image" -c 'stat -c %u /nix/store')
            [ "$owner" = "1001" ] || { echo "FAIL: /nix/store owner is '$owner', expected '1001'"; exit 1; }

            echo "==> Verifying custom experimental features in nix.conf (case 4)"
            conf=$($runtime run --rm --entrypoint sh "$image" -c 'cat /etc/nix/nix.conf')
            echo "$conf" | grep -q 'pipe-operators' || { echo "FAIL: nix.conf missing pipe-operators"; exit 1; }
            echo "$conf" | grep -q 'nix-command' || { echo "FAIL: nix.conf missing nix-command"; exit 1; }
            echo "$conf" | grep -q 'flakes' || { echo "FAIL: nix.conf missing flakes"; exit 1; }

            echo "==> Verifying extraEnv is present alongside nix env vars (case 7)"
            $runtime run --rm --entrypoint sh "$image" -c '
              [ "$MY_VAR" = "test-value" ] || { echo "FAIL: MY_VAR=$MY_VAR, expected test-value"; exit 1; }
              [ "$NIX_CONF_DIR" = "/etc/nix" ] || { echo "FAIL: NIX_CONF_DIR=$NIX_CONF_DIR, expected /etc/nix"; exit 1; }
              [ -n "$NIX_PATH" ] || { echo "FAIL: NIX_PATH is empty"; exit 1; }
              echo "    MY_VAR=$MY_VAR"
              echo "    NIX_CONF_DIR=$NIX_CONF_DIR"
              echo "    NIX_PATH=$NIX_PATH"
            '

            echo "==> All nix-custom checks passed"
          '';
        in {
          type = "app";
          program = "${script}";
        };

        apps.smoke-test-custom = let
          script = pkgs.writeShellScript "smoke-test-custom" ''
            set -euo pipefail

            image="localhost/agent-images/custom-test:latest"

            if command -v podman &>/dev/null; then
              runtime=podman
            elif command -v docker &>/dev/null; then
              runtime=docker
            else
              echo "ERROR: neither podman nor docker found"
              exit 1
            fi

            echo "==> Building custom-test image"
            nix build ".#custom-test-image"

            echo "==> Loading image ($runtime)"
            $runtime load < result

            echo "==> Verifying custom user and uid"
            output=$($runtime run --rm --entrypoint sh "$image" -c 'whoami && id -u')
            user=$(echo "$output" | sed -n '1p')
            uid_val=$(echo "$output" | sed -n '2p')
            [ "$user" = "dev" ] || { echo "FAIL: user is '$user', expected 'dev'"; exit 1; }
            [ "$uid_val" = "1002" ] || { echo "FAIL: uid is '$uid_val', expected '1002'"; exit 1; }

            echo "==> Verifying custom HOME"
            home=$($runtime run --rm --entrypoint sh "$image" -c 'echo $HOME')
            [ "$home" = "/home/dev" ] || { echo "FAIL: HOME is '$home', expected '/home/dev'"; exit 1; }

            echo "==> Verifying custom workingDir"
            workdir=$($runtime run --rm --entrypoint sh "$image" -c 'pwd')
            [ "$workdir" = "/project" ] || { echo "FAIL: workdir is '$workdir', expected '/project'"; exit 1; }

            echo "==> Verifying extraPackages (hello)"
            $runtime run --rm --entrypoint sh "$image" -c 'hello'

            echo "==> Verifying extraEnv"
            $runtime run --rm --entrypoint sh "$image" -c '
              [ "$CUSTOM_VAR" = "custom-value" ] || { echo "FAIL: CUSTOM_VAR=$CUSTOM_VAR, expected custom-value"; exit 1; }
              echo "    CUSTOM_VAR=$CUSTOM_VAR"
            '

            echo "==> Verifying nix is NOT available"
            if $runtime run --rm --entrypoint sh "$image" -c 'command -v nix' 2>/dev/null; then
              echo "FAIL: nix should not be present"
              exit 1
            fi

            echo "==> All custom checks passed"
          '';
        in {
          type = "app";
          program = "${script}";
        };
      }
    );
}
