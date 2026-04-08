setup_file() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  build_and_load "nix-ld-minimal-test-image"
}

setup() {
  load helpers
  RUNTIME=$(detect_runtime)
  export RUNTIME
  IMAGE="localhost/agent-images/nix-ld-minimal-test:latest"
}

@test "NIX_LD_LIBRARY_PATH contains only the custom libraries" {
  # This image uses nixLdLibraries = [ zlib openssl ], replacing the
  # defaults. Verify the library path does not contain packages from
  # the default set (e.g. libsodium) that were not explicitly listed.
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    echo "$NIX_LD_LIBRARY_PATH" | grep -qv "libsodium"
  '
  [[ ${status} -eq 0 ]]
}

@test "NIX_LD_LIBRARY_PATH contains zlib" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    echo "$NIX_LD_LIBRARY_PATH" | grep -q "zlib"
  '
  [[ ${status} -eq 0 ]]
}

@test "NIX_LD_LIBRARY_PATH contains openssl" {
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    echo "$NIX_LD_LIBRARY_PATH" | grep -q "openssl"
  '
  [[ ${status} -eq 0 ]]
}

@test "nix-ld runs a binary with minimal library set" {
  # hello only needs glibc, which is resolved via NIX_LD directly.
  # This verifies nix-ld works with a reduced library set.
  # shellcheck disable=SC2016
  run run_in -- "${IMAGE}" '
    cp "$(command -v hello)" /tmp/hello-foreign
    chmod u+w /tmp/hello-foreign
    patchelf --set-interpreter "$EXPECTED_NIX_LD_LINK_PATH" --remove-rpath /tmp/hello-foreign
    /tmp/hello-foreign | grep -q "Hello, world!"
  '
  [[ ${status} -eq 0 ]]
}
