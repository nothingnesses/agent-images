{
  description = "Sandboxed OCI container images for AI coding agents";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    llm-agents.url = "github:numtide/llm-agents.nix";
    agent-box.url = "github:0xferrous/agent-box";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      systems,
      llm-agents,
      agent-box,
      treefmt-nix,
      git-hooks,
      ...
    }:
    let
      allSystems = import systems;
      linuxSystems = builtins.filter (s: builtins.match ".*-linux" s != null) allSystems;
      eachSystem = nixpkgs.lib.genAttrs allSystems;
      eachLinuxSystem = nixpkgs.lib.genAttrs linuxSystems;

      perSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = pkgs.lib;
          agents = llm-agents.packages.${system};

          mkAgentImage = import ./lib/mkAgentImage.nix { inherit pkgs lib; };

          ab = agent-box.packages.${system}.default;

          agentConfigs = {
            # AI Coding Agents
            amp = { };
            claude-code = { };
            cli-proxy-api = { };
            code = { };
            codex = { };
            copilot-cli = { };
            crush = { };
            cursor-agent = { };
            droid = { };
            eca = { };
            forge = { };
            gemini-cli = { };
            goose-cli = { };
            iflow-cli = { };
            jules = { };
            kilocode-cli = { };
            letta-code = { };
            mistral-vibe = { };
            nanocoder = { };
            oh-my-opencode = { };
            omp = { };
            opencode = { };
            pi = { };
            qoder-cli = { };
            qwen-code = { };
            # AI Assistants
            hermes-agent = { };
            localgpt = { };
            openclaw = { };
            picoclaw = { };
            zeroclaw = { };
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
            withNixLd = true;
            user = "ci";
            uid = 1001;
            gid = 100;
            nixExperimentalFeatures = [
              "nix-command"
              "flakes"
              "pipe-operators"
            ];
            extraPackages = [
              pkgs.hello
              pkgs.patchelf
            ];
            extraEnv = {
              MY_VAR = "test-value";
            };
          };

          customTestImage = mkAgentImage {
            name = "agent-images/custom-test";
            agent = agents.opencode;
            entrypoint = [ agents.opencode.meta.mainProgram ];
            user = "dev";
            uid = 1002;
            gid = 100;
            workingDir = "/project";
            extraPackages = [ pkgs.hello ];
            extraEnv = {
              CUSTOM_VAR = "custom-value";
              XDG_CONFIG_HOME = "/home/dev/.custom-config";
            };
            extraDirectories = [
              "~"
              "~/.dev-cache"
              "~/.custom-config"
              "~/.my+app@v2"
              "/opt/dev-cache"
            ];
          };

          testsDir = ./tests;

          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              shfmt = {
                enable = true;
                indent_size = 2;
                includes = [
                  "*.sh"
                  "*.bash"
                  "*.bats"
                ];
              };
              prettier = {
                enable = true;
                includes = [
                  "*.md"
                  "*.yml"
                  "*.yaml"
                ];
              };
            };
          };

          pre-commit-check = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              treefmt = {
                enable = true;
                package = treefmtEval.config.build.wrapper;
              };
              deadnix = {
                enable = true;
                package = pkgs.deadnix;
              };
              actionlint = {
                enable = true;
                package = pkgs.actionlint;
              };
            };
          };

          mkTest =
            {
              name,
              vars ? { },
            }:
            let
              varDefs = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") vars);
              script = pkgs.writeShellScript name ''
                set -euo pipefail
                ${varDefs}
                ${pkgs.bats}/bin/bats ${testsDir}/${name}.bats
              '';
            in
            {
              type = "app";
              program = "${script}";
            };
        in
        {
          packages =
            (lib.mapAttrs (
              name: cfg:
              let
                agent = agents.${cfg.agentPkg or name};
              in
              mkAgentImage {
                name = "agent-images/${name}";
                inherit agent;
                entrypoint = [ agent.meta.mainProgram ];
                extraPackages = cfg.extraPackages or [ ];
                extraEnv = cfg.extraEnv or { };
              }
            ) agentConfigs)
            // {
              nix-test-image = nixTestImage;
              nix-test-image-custom = nixTestImageCustom;
              custom-test-image = customTestImage;
            };

          formatter = treefmtEval.config.build.wrapper;

          checks =
            let
              assertRejects =
                name: dirs:
                let
                  result = builtins.tryEval (mkAgentImage {
                    name = "assert-test";
                    agent = agents.opencode;
                    entrypoint = [ agents.opencode.meta.mainProgram ];
                    extraDirectories = dirs;
                  });
                in
                assert !result.success;
                pkgs.runCommand "assert-rejects-${name}" { } "touch $out";
            in
            {
              inherit pre-commit-check;
              assert-rejects-relative-path = assertRejects "relative-path" [ "relative/path" ];
              assert-rejects-denied-prefix-etc = assertRejects "denied-prefix-etc" [ "/etc/shadow" ];
              assert-rejects-denied-prefix-var = assertRejects "denied-prefix-var" [ "/var/data" ];
              assert-rejects-dotdot-traversal = assertRejects "dotdot-traversal" [ "/nix/../etc" ];
              assert-rejects-whitespace = assertRejects "whitespace" [ "/foo bar" ];
              assert-rejects-bare-denied = assertRejects "bare-denied" [ "/etc" ];
            };

          devShells.default = pkgs.mkShell {
            packages = [
              ab
              pkgs.actionlint
              pkgs.bats
              pkgs.deadnix
              pkgs.shellcheck
            ];
            inherit (pre-commit-check) shellHook;
          };

          apps = {
            test-default = mkTest { name = "default"; };
            test-nix = mkTest { name = "nix"; };
            test-nix-install = mkTest {
              name = "nix-install";
              vars.SYSTEM = system;
            };
            test-nix-custom = mkTest { name = "nix-custom"; };
            test-nix-userns = mkTest { name = "nix-userns"; };
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
                ${pkgs.shellcheck}/bin/shellcheck --enable=all ${testsDir}/*.bats ${testsDir}/*.bash
              ''}";
            };
            deadnix = {
              type = "app";
              program = "${pkgs.writeShellScript "deadnix" ''
                ${pkgs.deadnix}/bin/deadnix --fail .
              ''}";
            };
            actionlint = {
              type = "app";
              program = "${pkgs.writeShellScript "actionlint" ''
                ${pkgs.actionlint}/bin/actionlint
              ''}";
            };
            lint = {
              type = "app";
              program = "${pkgs.writeShellScript "lint" ''
                set -euo pipefail
                ${pkgs.shellcheck}/bin/shellcheck --enable=all ${testsDir}/*.bats ${testsDir}/*.bash
                ${pkgs.deadnix}/bin/deadnix --fail .
                ${pkgs.actionlint}/bin/actionlint
              ''}";
            };
          };
        };
    in
    {
      lib.mkAgentImage =
        {
          pkgs,
          lib ? pkgs.lib,
        }:
        import ./lib/mkAgentImage.nix { inherit pkgs lib; };

      packages = eachLinuxSystem (system: (perSystem system).packages);
      formatter = eachSystem (system: (perSystem system).formatter);
      checks = eachSystem (system: (perSystem system).checks);
      devShells = eachSystem (system: (perSystem system).devShells);
      apps = eachLinuxSystem (system: (perSystem system).apps);
    };
}
