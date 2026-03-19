setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "nix-test-image"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  IMAGE="localhost/agent-images/nix-test:latest"
  : "${SYSTEM:?SYSTEM must be set}"
}

@test "runtime package installation with nix-shell" {
  run run_in "${IMAGE}" 'nix-shell -p hello --command hello'
  [[ ${status} -eq 0 ]]
}

@test "nix develop works with a flake" {
  run "${RUNTIME}" run --rm --entrypoint sh "${IMAGE}" -c "
    mkdir -p /tmp/test-flake
    cat > /tmp/test-flake/flake.nix <<FLAKE
{
  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixpkgs-unstable\";
  outputs = { nixpkgs, ... }:
    let pkgs = import nixpkgs { system = \"${SYSTEM}\"; };
    in { devShells.${SYSTEM}.default = pkgs.mkShell { buildInputs = [ pkgs.hello ]; }; };
}
FLAKE
    cd /tmp/test-flake
    nix develop --command hello
  "
  [[ ${status} -eq 0 ]]
}
