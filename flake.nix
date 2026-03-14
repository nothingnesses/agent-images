{
  description = "OCI container images for AI coding agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, llm-agents, flake-utils }:
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
      in
      {
        packages = {
          claude-code = import ./agents/claude-code.nix { inherit mkAgentImage agents pkgs; };
          codex = import ./agents/codex.nix { inherit mkAgentImage agents pkgs; };
          gemini = import ./agents/gemini.nix { inherit mkAgentImage agents pkgs; };
          opencode = import ./agents/opencode.nix { inherit mkAgentImage agents pkgs; };
        };
      }
    );
}
