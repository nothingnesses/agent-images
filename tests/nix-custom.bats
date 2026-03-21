setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "nix-test-image-custom"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  IMAGE="localhost/agent-images/nix-test-custom:latest"
}

@test "custom user is ci" {
  run run_in -- "${IMAGE}" whoami
  [[ ${status} -eq 0 ]]
  [[ ${output} == "ci" ]]
}

@test "custom uid is 1001" {
  run run_in -- "${IMAGE}" 'id -u'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "1001" ]]
}

@test "custom gid is 100" {
  run run_in -- "${IMAGE}" 'id -g'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "100" ]]
}

@test "nix works with custom user" {
  run run_in -- "${IMAGE}" 'nix --version'
  [[ ${status} -eq 0 ]]
}

@test "/nix/store is writable by custom user" {
  run run_in -- "${IMAGE}" 'touch /nix/store/.write-test && rm /nix/store/.write-test'
  [[ ${status} -eq 0 ]]
}

@test "/nix/store is owned by custom uid:gid" {
  run run_in -- "${IMAGE}" 'stat -c %u:%g /nix/store'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "1001:100" ]]
}

@test "nix.conf has pipe-operators" {
  run run_in -- "${IMAGE}" 'cat /etc/nix/nix.conf'
  [[ ${status} -eq 0 ]]
  [[ ${output} == *"pipe-operators"* ]]
}

@test "nix.conf has nix-command" {
  run run_in -- "${IMAGE}" 'cat /etc/nix/nix.conf'
  [[ ${status} -eq 0 ]]
  [[ ${output} == *"nix-command"* ]]
}

@test "nix.conf has flakes" {
  run run_in -- "${IMAGE}" 'cat /etc/nix/nix.conf'
  [[ ${status} -eq 0 ]]
  [[ ${output} == *"flakes"* ]]
}

@test "extraEnv MY_VAR is set" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $MY_VAR'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "test-value" ]]
}

@test "NIX_CONF_DIR is set with custom config" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $NIX_CONF_DIR'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/etc/nix" ]]
}

@test "NIX_PATH is set with custom config" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $NIX_PATH'
  [[ ${status} -eq 0 ]]
  [[ -n ${output} ]]
}
