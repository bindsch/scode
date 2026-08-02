#!/usr/bin/env bash
# Shared helpers for scode test suite

SCODE_SOURCE="$BATS_TEST_DIRNAME/../scode"
SCODE="${SCODE_UNDER_TEST:-$SCODE_SOURCE}"
NO_SANDBOX_JS="$BATS_TEST_DIRNAME/../lib/no-sandbox.js"

# Use a real temp dir as the project directory so path validation passes
setup() {
  TEST_PROJECT="$(mktemp -d)"
  _EXTRA_CLEANUP_DIRS=()
  unset SCODE_CONFIG
  unset SCODE_NET
  unset SCODE_FS_MODE
}

teardown() {
  rm -rf "$TEST_PROJECT"
  for _dir in "${_EXTRA_CLEANUP_DIRS[@]}"; do
    rm -rf "$_dir"
  done
}

# Register a directory for cleanup in teardown (safe even on test failure)
track_cleanup() {
  _EXTRA_CLEANUP_DIRS+=("$1")
}

require_node() {
  command -v node >/dev/null 2>&1 || skip "node not installed"
}

# Some preload tests exercise rewriting through a wrapper binary such as
# `timeout` or `stdbuf`. These ship with GNU coreutils and are absent on stock
# macOS, so the behavior can only be asserted where the wrapper actually exists.
require_command() {
  command -v "$1" >/dev/null 2>&1 || skip "$1 not installed"
}

# bubblewrap can be installed yet unusable: Ubuntu 24.04 confines unprivileged
# user namespaces through AppArmor, and most containers block them outright.
# Probe an actual sandbox rather than trusting that the binary exists.
require_linux_bwrap() {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  bwrap --ro-bind / / --dev /dev --proc /proc -- /bin/true >/dev/null 2>&1 \
    || skip "bubblewrap cannot create a sandbox in this environment"
}

# ---------- Platform-aware dry-run assertions ----------
#
# The dry-run rendering differs by platform: macOS prints an SBPL profile, Linux
# prints the bubblewrap argv. These helpers assert the intended behavior so one
# test covers both platforms instead of hardcoding one platform's syntax.

# Linux renders the argv shell-quoted, so a path containing spaces or a hash
# appears escaped. Accept either rendering.
assert_output_has_path() {
  local output="$1" path="$2" escaped
  escaped="$(printf '%q' "$path")"
  [[ "$output" == *"$path"* || "$output" == *"$escaped"* ]]
}

assert_dry_run_command() {
  local output="$1" command_word="$2"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    [[ "$output" == *"# Command: $command_word"* ]]
  else
    [[ "$output" == *" -- $command_word"* ]]
  fi
}

# Strict/non-strict and project read-write assertions already exist further down
# as assert_strict_mode_output, assert_non_strict_mode_output, and
# assert_project_read_write_output. Use those.

dry_run_cmd() {
  "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

# Some tests require launching an actual sandboxed command (not just dry-run).
# In restricted CI/sandbox environments, nested sandbox-exec can fail; skip those.
require_runtime_sandbox() {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"

  # If sandbox-exec itself cannot run, this host cannot run runtime tests.
  /usr/bin/sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
    || skip "runtime sandbox unavailable in this environment"

  # If the host sandbox works but scode probe fails, fail the test.
  run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

require_any_runtime_sandbox() {
  case "$(uname -s)" in
    Darwin)
      require_runtime_sandbox
      ;;
    Linux)
      [[ -x /usr/bin/bwrap ]] || skip "bubblewrap unavailable"
      /usr/bin/bwrap --ro-bind / / --dev /dev --proc /proc -- /usr/bin/true >/dev/null 2>&1 \
        || skip "runtime sandbox unavailable in this environment"
      run "$SCODE" -C "$TEST_PROJECT" -- true
      [ "$status" -eq 0 ]
      ;;
    *)
      skip "runtime sandbox unsupported on this platform"
      ;;
  esac
}

linux_dry_run() {
  _SCODE_PLATFORM=linux "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

darwin_dry_run() {
  _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

assert_dry_run_generated() {
  local out="$1"
  [[ "$out" == *"(version 1)"* || "$out" == *"bwrap --new-session"* ]]
}

assert_network_disabled_output() {
  local out="$1"
  [[ "$out" == *"(deny network"* || \
     "$out" == *"--unshare-net"* || \
     ( "$out" == *"(deny default)"* && "$out" != *"(allow network"* ) ]]
}

assert_network_enabled_output() {
  local out="$1"
  [[ "$out" != *"(deny network"* ]]
  [[ "$out" != *"--unshare-net"* ]]
}

assert_project_read_only_output() {
  local out="$1"
  local project_dir="$2"
  local project_real
  project_real="$(cd "$project_dir" && pwd -P)"
  [[ "$out" == *"(deny file-write*"* || \
     ( "$out" == *"Project directory (read-only)"* && "$out" == *"(subpath \"${project_real}\")"* ) || \
     "$out" == *"--ro-bind ${project_dir} ${project_dir}"* || \
     "$out" == *"--ro-bind ${project_real} ${project_real}"* ]]
}

assert_project_read_write_output() {
  local out="$1"
  local project_dir="$2"
  local project_real
  project_real="$(cd "$project_dir" && pwd -P)"
  [[ "$out" != *"(deny file-write*"* ]]
  [[ "$out" != *"--ro-bind ${project_dir} ${project_dir}"* ]]
  [[ "$out" != *"--ro-bind ${project_real} ${project_real}"* ]]
}

assert_strict_mode_output() {
  local out="$1"
  [[ "$out" == *"(deny default)"* || "$out" == *"# Mode: strict"* ]]
}

assert_non_strict_mode_output() {
  local out="$1"
  [[ "$out" != *"(deny default)"* ]]
  [[ "$out" != *"# Mode: strict"* ]]
}
