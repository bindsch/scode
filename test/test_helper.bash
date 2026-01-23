#!/usr/bin/env bash
# Shared helpers for scode test suite

SCODE="$BATS_TEST_DIRNAME/../scode"
NO_SANDBOX_JS="$BATS_TEST_DIRNAME/../lib/no-sandbox.js"

# Use a real temp dir as the project directory so path validation passes
setup() {
  TEST_PROJECT="$(mktemp -d)"
  unset SCODE_CONFIG
  unset SCODE_NET
  unset SCODE_FS_MODE
}

teardown() {
  rm -rf "$TEST_PROJECT"
}

require_node() {
  command -v node >/dev/null 2>&1 || skip "node not installed"
}

dry_run_cmd() {
  "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

# Some tests require launching an actual sandboxed command (not just dry-run).
# In restricted CI/sandbox environments, nested sandbox-exec can fail; skip those.
require_runtime_sandbox() {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"

  # If sandbox-exec itself cannot run, this host cannot run runtime tests.
  sandbox-exec -p '(version 1) (allow default)' true >/dev/null 2>&1 \
    || skip "runtime sandbox unavailable in this environment"

  # If the host sandbox works but scode probe fails, fail the test.
  run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

linux_dry_run() {
  _SCODE_PLATFORM=linux "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

linux_runtime() {
  _SCODE_PLATFORM=linux "$SCODE" -C "$TEST_PROJECT" -- "$@"
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
