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

        # Test images
        nixTestImage = mkAgentImage {
          name = "agent-images/nix-test";
          agent = agents.opencode;
          entrypoint = [ agents.opencode.meta.mainProgram ];
          withNix = true;
        };

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

        testsDir = ./tests;

        mkTest = { name, vars ? {} }: let
          varDefs = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") vars);
          script = pkgs.writeShellScript name ''
            set -euo pipefail
            ${varDefs}
            ${pkgs.bats}/bin/bats ${testsDir}/${name}.bats
          '';
        in {
          type = "app";
          program = "${script}";
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
          packages = [ ab pkgs.bats pkgs.shellcheck ];
        };

        apps = {
          test-default = mkTest { name = "default"; };
          test-nix = mkTest { name = "nix"; };
          test-nix-install = mkTest {
            name = "nix-install";
            vars.SYSTEM = system;
          };
          test-nix-custom = mkTest { name = "nix-custom"; };
          test-custom = mkTest { name = "custom"; };
          test = {
            type = "app";
            program = "${pkgs.writeShellScript "test" ''
              set -euo pipefail
              export SYSTEM="${system}"
              ${pkgs.bats}/bin/bats ${testsDir}
            ''}";
          };
          shellcheck = {
            type = "app";
            program = "${pkgs.writeShellScript "shellcheck" ''
              ${pkgs.shellcheck}/bin/shellcheck --enable=all --exclude=SC2292 ${testsDir}/*.bats ${testsDir}/*.bash
            ''}";
          };
        };
      }
    );
}
