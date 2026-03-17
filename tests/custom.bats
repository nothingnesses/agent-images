setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "custom-test-image"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  IMAGE="localhost/agent-images/custom-test:latest"
}

@test "custom user is dev" {
  run run_in "${IMAGE}" whoami
  [[ ${status} -eq 0 ]]
  [[ ${output} == "dev" ]]
}

@test "custom uid is 1002" {
  run run_in "${IMAGE}" 'id -u'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "1002" ]]
}

@test "HOME is /home/dev" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" 'echo $HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/dev" ]]
}

@test "working directory is /project" {
  run run_in "${IMAGE}" pwd
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/project" ]]
}

@test "extraPackages hello is available" {
  run run_in "${IMAGE}" hello
  [[ ${status} -eq 0 ]]
}

@test "extraEnv CUSTOM_VAR is set" {
  # shellcheck disable=SC2016
  run run_in "${IMAGE}" 'echo $CUSTOM_VAR'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "custom-value" ]]
}

@test "nix is not available" {
  run run_in "${IMAGE}" 'command -v nix'
  [[ ${status} -ne 0 ]]
}
