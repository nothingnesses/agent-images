# Load the Nix development environment via direnv for all recipes.
# In CI, set SKIP_DIRENV=1 to bypass (Nix environment is already active).
set shell := ["bash", "-c"]
skip_direnv := env_var_or_default("SKIP_DIRENV", "")
direnv_prefix := if skip_direnv != "" { "" } else { "direnv allow && eval \"$(direnv export bash)\" &&" }

# List available recipes.
default:
    @just --list

# Format all files (Nix, shell, Markdown, YAML).
fmt *args:
    {{direnv_prefix}} nix fmt {{args}}

# Run all linters (shellcheck, deadnix, actionlint).
lint:
    {{direnv_prefix}} nix run .#lint

# Run shellcheck on test files.
shellcheck:
    {{direnv_prefix}} nix run .#shellcheck

# Run deadnix to find unused Nix bindings.
deadnix:
    {{direnv_prefix}} nix run .#deadnix

# Run actionlint on CI workflow files.
actionlint:
    {{direnv_prefix}} nix run .#actionlint

# Run a specific test suite. Example: just test nix-ld
test name:
    {{direnv_prefix}} nix run .#test-{{name}}

# Run all test suites.
test-all:
    {{direnv_prefix}} nix run .#test

# Verify: format check, lint, then all tests (in order).
verify:
    just fmt -- --ci
    just lint
    just test-all
