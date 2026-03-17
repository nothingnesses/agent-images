# Common helpers for BATS smoke tests

detect_runtime() {
  if command -v podman &>/dev/null; then
    echo podman
  elif command -v docker &>/dev/null; then
    echo docker
  else
    echo "ERROR: neither podman nor docker found" >&2
    return 1
  fi
}

build_and_load() {
  local attr="$1"
  nix build ".#${attr}"
  # shellcheck disable=SC2154 # RUNTIME is set by the caller
  "${RUNTIME}" load < result
}

run_in() {
  local image="$1"; shift
  # shellcheck disable=SC2154 # RUNTIME is set by the caller
  "${RUNTIME}" run --rm --entrypoint sh "${image}" -c "$*"
}
