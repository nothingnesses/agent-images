setup_file() {
  load test_helper
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "${AGENT:-opencode}"
}

setup() {
  load test_helper
  RUNTIME=$(detect_runtime)
  export RUNTIME
  AGENT="${AGENT:-opencode}"
  IMAGE="localhost/agent-images/${AGENT}:latest"
}

@test "agent runs --version" {
  run "${RUNTIME}" run --rm "${IMAGE}" --version
  [ "${status}" -eq 0 ]
}

@test "user is agent" {
  run run_in "${IMAGE}" whoami
  [ "${status}" -eq 0 ]
  [ "${output}" = "agent" ]
}

@test "HOME is /home/agent" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" 'echo $HOME'
  [ "${status}" -eq 0 ]
  [ "${output}" = "/home/agent" ]
}

@test "working directory is /workspace" {
  run run_in "${IMAGE}" pwd
  [ "${status}" -eq 0 ]
  [ "${output}" = "/workspace" ]
}

@test "git is available" {
  run run_in "${IMAGE}" 'command -v git'
  [ "${status}" -eq 0 ]
}

@test "rg is available" {
  run run_in "${IMAGE}" 'command -v rg'
  [ "${status}" -eq 0 ]
}

@test "nix is not available by default" {
  run run_in "${IMAGE}" 'command -v nix'
  [ "${status}" -ne 0 ]
}

@test "/tmp is writable" {
  run run_in "${IMAGE}" 'touch /tmp/test-file && rm /tmp/test-file'
  [ "${status}" -eq 0 ]
}

@test "HOME is writable" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" 'touch $HOME/test-file && rm $HOME/test-file'
  [ "${status}" -eq 0 ]
}

@test "SSL_CERT_FILE is set and exists" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" '[ -n "$SSL_CERT_FILE" ] && [ -f "$SSL_CERT_FILE" ]'
  [ "${status}" -eq 0 ]
}
