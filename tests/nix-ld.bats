setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "nix-ld-test-image"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  IMAGE="localhost/agent-images/nix-ld-test:latest"
}

@test "nix is not available" {
  run run_in -- "${IMAGE}" 'command -v nix'
  [[ ${status} -ne 0 ]]
}

@test "nix-ld is available" {
  run run_in -- "${IMAGE}" 'command -v nix-ld'
  [[ ${status} -eq 0 ]]
}

@test "NIX_LD env vars are set" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    [ -n "$NIX_LD" ] &&
    [ -x "$NIX_LD" ] &&
    [ -n "$NIX_LD_LIBRARY_PATH" ]
  '
  [[ ${status} -eq 0 ]]
}

@test "NIX_LD_LIBRARY_PATH directories exist and contain shared objects" {
  # Verify that every directory in NIX_LD_LIBRARY_PATH is present in the
  # image and contains .so files. Catches nixpkgs updates that change a
  # package's output structure or break the string context mechanism.
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    IFS=: read -ra dirs <<< "$NIX_LD_LIBRARY_PATH"
    [ ${#dirs[@]} -gt 0 ] || exit 1
    for dir in "${dirs[@]}"; do
      [ -d "$dir" ] || { echo "missing: $dir"; exit 1; }
      ls "$dir"/*.so* >/dev/null 2>&1 || { echo "no .so files in: $dir"; exit 1; }
    done
  '
  [[ ${status} -eq 0 ]]
}

@test "dynamic linker symlink exists at expected path" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    [ -n "$EXPECTED_NIX_LD_LINK_PATH" ] || exit 1
    [ -L "$EXPECTED_NIX_LD_LINK_PATH" ]
  '
  [[ ${status} -eq 0 ]]
}

@test "dynamic linker symlink points to nix-ld" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    [ "$(readlink -f "$EXPECTED_NIX_LD_LINK_PATH")" = "$(readlink -f "$(command -v nix-ld)")" ]
  '
  [[ ${status} -eq 0 ]]
}

@test "NIX_LD points to the real dynamic linker, not nix-ld" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    [ -n "$EXPECTED_NIX_LD" ] &&
    [ "$(readlink -f "$NIX_LD")" = "$(readlink -f "$EXPECTED_NIX_LD")" ] &&
    [ "$(readlink -f "$NIX_LD")" != "$(readlink -f "$(command -v nix-ld)")" ]
  '
  [[ ${status} -eq 0 ]]
}

@test "nix-ld runs an unpatched binary via the conventional loader path" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    cp "$(command -v hello)" /tmp/hello-foreign
    chmod u+w /tmp/hello-foreign
    patchelf --set-interpreter "$EXPECTED_NIX_LD_LINK_PATH" --remove-rpath /tmp/hello-foreign
    /tmp/hello-foreign | grep -q "Hello, world!"
  '
  [[ ${status} -eq 0 ]]
}

@test "NIX_LD_LIBRARY_PATH resolves non-glibc libraries" {
  # bzip2 links against libbz2 (from pkgs.bzip2, in the default nix-ld
  # library set) and glibc. Stripping the RPATH forces libbz2 resolution
  # through NIX_LD_LIBRARY_PATH rather than the baked-in store path.
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    cp "$(command -v bzip2)" /tmp/bzip2-foreign
    chmod u+w /tmp/bzip2-foreign
    patchelf --set-interpreter "$EXPECTED_NIX_LD_LINK_PATH" --remove-rpath /tmp/bzip2-foreign
    /tmp/bzip2-foreign --help 2>&1 | grep -qi "bzip2"
  '
  [[ ${status} -eq 0 ]]
}
