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
}

@test "nix is available" {
  run run_in -- "${IMAGE}" 'nix --version'
  [[ ${status} -eq 0 ]]
}

@test "store DB is populated" {
  run run_in -- "${IMAGE}" 'nix path-info --all | wc -l'
  [[ ${status} -eq 0 ]]
  [[ ${output} -gt 0 ]]
}

@test "nix store is writable" {
  run run_in -- "${IMAGE}" 'touch /nix/store/.write-test && rm /nix/store/.write-test'
  [[ ${status} -eq 0 ]]
}

@test "store path query works" {
  path=$(run_in -- "${IMAGE}" 'nix path-info --all | head -1')
  run run_in -- "${IMAGE}" "nix path-info ${path}"
  [[ ${status} -eq 0 ]]
}

@test "nix.conf has sandbox disabled" {
  run run_in -- "${IMAGE}" 'cat /etc/nix/nix.conf'
  [[ ${status} -eq 0 ]]
  [[ ${output} == *"sandbox = false"* ]]
}

@test "nix.conf has expected experimental features" {
  run run_in -- "${IMAGE}" 'cat /etc/nix/nix.conf'
  [[ ${status} -eq 0 ]]
  [[ ${output} == *"experimental-features = nix-command flakes"* ]]
}

@test "NIX_CONF_DIR is set correctly" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $NIX_CONF_DIR'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/etc/nix" ]]
}

@test "NIX_PATH is set" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $NIX_PATH'
  [[ ${status} -eq 0 ]]
  [[ -n ${output} ]]
}
