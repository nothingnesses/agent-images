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
      }
    );
}
