setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "minimal-test-image"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  IMAGE="localhost/agent-images/minimal-test:latest"
}

@test "shell is available" {
  run run_in -- "${IMAGE}" 'echo ok'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "ok" ]]
}

@test "coreutils work" {
  run run_in -- "${IMAGE}" 'ls / && whoami && id'
  [[ ${status} -eq 0 ]]
}

@test "CA certificates are present" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '[ -f "$SSL_CERT_FILE" ]'
  [[ ${status} -eq 0 ]]
}

@test "HOME and working directory are correct" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo "$HOME" && pwd'
  [[ ${status} -eq 0 ]]
  [[ ${output} == *"/home/agent"* ]]
  [[ ${output} == *"/workspace"* ]]
}

@test "tmp is writable" {
  run run_in -- "${IMAGE}" 'touch /tmp/test && rm /tmp/test'
  [[ ${status} -eq 0 ]]
}

@test "XDG base directories exist and are writable" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    for dir in "$HOME/.config" "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/state"; do
      [ -d "$dir" ] || exit 1
      touch "$dir/.write-test" || exit 1
      rm "$dir/.write-test" || exit 1
    done
  '
  [[ ${status} -eq 0 ]]
}

@test "non-default base packages are absent" {
  # The minimal image only has bash, coreutils, and cacert.
  # Verify that packages from the default set are not present.
  run run_in -- "${IMAGE}" 'command -v git'
  [[ ${status} -ne 0 ]]
}
