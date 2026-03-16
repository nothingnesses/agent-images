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
        pkgs = nixpkgs.legacyPackages.${system};
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
          claude-code = {
            entrypoint = "claude";
            extraPackages = [ pkgs.nodejs ];
          };
          codex = {};
          gemini = { agentPkg = "gemini-cli"; };
          opencode = {};
        };
      in
      {
        packages = lib.mapAttrs (name: cfg:
          mkAgentImage {
            name = "agent-images/${name}";
            agent = agents.${cfg.agentPkg or name};
            entrypoint = [ (cfg.entrypoint or name) ];
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
