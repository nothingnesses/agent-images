setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "${AGENT:-opencode}"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  AGENT="${AGENT:-opencode}"
  IMAGE="localhost/agent-images/${AGENT}:latest"
}

@test "agent runs --version" {
  run "${RUNTIME}" run --rm "${IMAGE}" --version
  [[ ${status} -eq 0 ]]
}

@test "user is agent" {
  run run_in "${IMAGE}" whoami
  [[ ${status} -eq 0 ]]
  [[ ${output} == "agent" ]]
}

@test "default gid matches uid" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" '[ "$(id -g)" = "$(id -u)" ]'
  [[ ${status} -eq 0 ]]
}

@test "HOME is /home/agent" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" 'echo $HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/agent" ]]
}

@test "working directory is /workspace" {
  run run_in "${IMAGE}" pwd
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/workspace" ]]
}

@test "git is available" {
  run run_in "${IMAGE}" 'command -v git'
  [[ ${status} -eq 0 ]]
}

@test "rg is available" {
  run run_in "${IMAGE}" 'command -v rg'
  [[ ${status} -eq 0 ]]
}

@test "nix is not available by default" {
  run run_in "${IMAGE}" 'command -v nix'
  [[ ${status} -ne 0 ]]
}

@test "/tmp is writable" {
  run run_in "${IMAGE}" 'touch /tmp/test-file && rm /tmp/test-file'
  [[ ${status} -eq 0 ]]
}

@test "HOME is writable" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" 'touch $HOME/test-file && rm $HOME/test-file'
  [[ ${status} -eq 0 ]]
}

@test "XDG base directories exist and are writable" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" '
    for dir in "$HOME/.config" "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/state"; do
      [ -d "$dir" ] || exit 1
      touch "$dir/.write-test" || exit 1
      rm "$dir/.write-test" || exit 1
    done
  '
  [[ ${status} -eq 0 ]]
}

@test "SSL_CERT_FILE is set and exists" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" '[ -n "$SSL_CERT_FILE" ] && [ -f "$SSL_CERT_FILE" ]'
  [[ ${status} -eq 0 ]]
}
