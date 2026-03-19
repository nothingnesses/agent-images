setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  if [[ ${RUNTIME} != "podman" ]]; then
    skip "--userns=keep-id is Podman-only"
  fi
  build_and_load "nix-test-image"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  if [[ ${RUNTIME} != "podman" ]]; then
    skip "--userns=keep-id is Podman-only"
  fi
  IMAGE="localhost/agent-images/nix-test:latest"
}

@test "nix store is writable with --userns=keep-id" {
  run run_in --userns=keep-id -- "${IMAGE}" 'touch /nix/store/.write-test && rm /nix/store/.write-test'
  [[ ${status} -eq 0 ]]
}

@test "/tmp is writable with --userns=keep-id" {
  run run_in --userns=keep-id -- "${IMAGE}" 'touch /tmp/test-file && rm /tmp/test-file'
  [[ ${status} -eq 0 ]]
}

@test "home is writable with --userns=keep-id" {
  # shellcheck disable=SC2016
  run run_in --userns=keep-id -- "${IMAGE}" 'touch $HOME/test-file && rm $HOME/test-file'
  [[ ${status} -eq 0 ]]
}

@test "runtime package installation with --userns=keep-id" {
  run run_in --userns=keep-id -- "${IMAGE}" 'nix-shell -p hello --command hello'
  [[ ${status} -eq 0 ]]
}
