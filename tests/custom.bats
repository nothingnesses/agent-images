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
  run run_in -- "${IMAGE}" whoami
  [[ ${status} -eq 0 ]]
  [[ ${output} == "dev" ]]
}

@test "custom uid is 1002" {
  run run_in -- "${IMAGE}" 'id -u'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "1002" ]]
}

@test "custom gid is 100" {
  run run_in -- "${IMAGE}" 'id -g'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "100" ]]
}

@test "HOME is /home/dev" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/dev" ]]
}

@test "default XDG base directories exist for custom user" {
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

@test "XDG_CONFIG_HOME is overridden by extraEnv" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $XDG_CONFIG_HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/dev/.custom-config" ]]
}

@test "overridden XDG_CONFIG_HOME directory exists and is writable" {
  run run_in -- "${IMAGE}" 'touch /home/dev/.custom-config/.write-test && rm /home/dev/.custom-config/.write-test'
  [[ ${status} -eq 0 ]]
}

@test "XDG_CACHE_HOME retains default when not overridden" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $XDG_CACHE_HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/dev/.cache" ]]
}

@test "XDG_DATA_HOME retains default when not overridden" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $XDG_DATA_HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/dev/.local/share" ]]
}

@test "XDG_STATE_HOME retains default when not overridden" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $XDG_STATE_HOME'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/home/dev/.local/state" ]]
}

@test "no duplicate XDG_CONFIG_HOME in env" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'env | grep -c "^XDG_CONFIG_HOME="'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "1" ]]
}

@test "working directory is /project" {
  run run_in -- "${IMAGE}" pwd
  [[ ${status} -eq 0 ]]
  [[ ${output} == "/project" ]]
}

@test "extraPackages hello is available" {
  run run_in -- "${IMAGE}" hello
  [[ ${status} -eq 0 ]]
}

@test "extraEnv CUSTOM_VAR is set" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" 'echo $CUSTOM_VAR'
  [[ ${status} -eq 0 ]]
  [[ ${output} == "custom-value" ]]
}

@test "extraDirectories are created and owned by the runtime user" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    [ -d "$HOME/.dev-cache" ] || exit 1
    [ "$(stat -c %u:%g "$HOME/.dev-cache")" = "1002:100" ] || exit 1
    [ "$(stat -c %u:%g /opt/dev-cache)" = "1002:100" ] || exit 1
  '
  [[ ${status} -eq 0 ]]
}

@test "extraDirectories with special characters exist" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    [ -d "$HOME/.my+app@v2" ] &&
    [ "$(stat -c %u:%g "$HOME/.my+app@v2")" = "1002:100" ]
  '
  [[ ${status} -eq 0 ]]
}

@test "tilde normalization resolves to custom home" {
  run run_in -- "${IMAGE}" '[ -d /home/dev/.dev-cache ]'
  [[ ${status} -eq 0 ]]
}

@test "extraDirectories intermediate parents outside HOME remain root-owned" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '[ "$(stat -c %u:%g /opt)" = "0:0" ]'
  [[ ${status} -eq 0 ]]
}

@test "nix is not available" {
  run run_in -- "${IMAGE}" 'command -v nix'
  [[ ${status} -ne 0 ]]
}
