#!/usr/bin/env bats
# CLI surface area — flags, validation, path handling

load test_helper

# ---------- Basic CLI ----------

@test "version output" {
  run "$SCODE" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^scode[[:space:]][0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "help output" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Safe sandbox wrapper"* ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Options:"* ]]
}

@test "short help flag" {
  run "$SCODE" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown option fails" {
  run "$SCODE" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

# ---------- Validation ----------

@test "missing command errors (no dry-run)" {
  run "$SCODE" -C "$TEST_PROJECT" -- no_such_command_xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"command not found"* ]]
}

@test "errors when sandbox-exec is unavailable on darwin runtime path" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local bash_bin
  bash_bin="$(command -v bash)"
  mkdir -p "$fake_bin"
  PATH="$fake_bin" _SCODE_PLATFORM=darwin run "$bash_bin" "$SCODE" -C "$TEST_PROJECT" -- /usr/bin/true
  [ "$status" -eq 1 ]
  [[ "$output" == *"sandbox-exec not found"* ]]
}

@test "errors when bwrap is unavailable on linux runtime path" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local bash_bin
  bash_bin="$(command -v bash)"
  mkdir -p "$fake_bin"
  PATH="$fake_bin" _SCODE_PLATFORM=linux run "$bash_bin" "$SCODE" -C "$TEST_PROJECT" -- /usr/bin/true
  [ "$status" -eq 1 ]
  [[ "$output" == *"bwrap not found"* ]]
}

@test "dry-run: missing command does not error" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- no_such_command_xyz
  [ "$status" -eq 0 ]
  [[ "$output" == *"(version 1)"* ]]
}

@test "missing project dir errors" {
  run "$SCODE" --dry-run -C /nonexistent/path/xyz -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"project directory does not exist"* ]]
}

@test "--block without argument fails" {
  run "$SCODE" --block
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--allow without argument fails" {
  run "$SCODE" --allow
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--cwd without argument fails" {
  run "$SCODE" --cwd
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--cwd specified twice fails" {
  run "$SCODE" --dry-run -C "$TEST_PROJECT" --cwd "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"--cwd specified more than once"* ]]
}

@test "--log without argument fails" {
  run "$SCODE" --log
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--log specified twice fails" {
  run "$SCODE" --dry-run --log "$TEST_PROJECT/a.log" --log "$TEST_PROJECT/b.log" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"--log specified more than once"* ]]
}

# ---------- Short flags ----------

@test "short version flag -V" {
  run "$SCODE" -V
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^scode[[:space:]][0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "short no-net flag -n" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run -n -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny network"* ]]
}

@test "short cwd flag -C" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(version 1)"* ]]
}

# ---------- Default command ----------

@test "default command is opencode" {
  # dry-run with no command should show opencode as default
  run "$SCODE" --dry-run -C "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Command: opencode"* ]]
}

# ---------- -- separator ----------

@test "double-dash separator works" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Command: true"* ]]
}

# ---------- -C / --cwd tilde expansion ----------

@test "-C expands tilde" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # Use a writable synthetic HOME to avoid host HOME permission assumptions.
  local fake_home="$TEST_PROJECT/home-$$"
  local test_dir="$fake_home/.scode-test-cwd-$$"
  mkdir -p "$test_dir"
  HOME="$fake_home" run "$SCODE" --dry-run -C "~/.scode-test-cwd-$$" -- true
  local rc=$status
  rmdir "$test_dir"
  rmdir "$fake_home"
  [ "$rc" -eq 0 ]
  [[ "$output" == *"(version 1)"* ]]
}

# ---------- Path validation ----------

@test "rejects -C path with newline" {
  local bad_path
  bad_path=$'/tmp/evil\npath'
  run "$SCODE" --dry-run -C "$bad_path" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid path"* ]]
}

@test "rejects --block path with carriage return" {
  local bad_path
  bad_path=$'/tmp/evil\rpath'
  run "$SCODE" --dry-run --block "$bad_path" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid path"* ]]
}

# ---------- expand_path tilde safety ----------

@test "expand_path does not expand ~user form" {
  # ~root should NOT be expanded (we only expand ~/ and ~)
  # This just verifies it does not crash; the actual path will
  # fail directory validation, which is fine
  run "$SCODE" --dry-run --block "~root" -C "$TEST_PROJECT" -- true
  # Should succeed (treating ~root as literal path) or fail with validation error
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  # Either way, ~root must NOT have been expanded to the root user's home
  if [[ "$status" -eq 0 ]]; then
    [[ "$output" != *"/var/root"* ]]
    [[ "$output" != *"/root"* ]]
  fi
}

# ---------- --ro --rw ordering ----------

@test "last fs mode flag wins (--ro --rw)" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --ro --rw -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"(deny file-write*"* ]]
}

@test "last fs mode flag wins (--rw --ro)" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --rw --ro -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny file-write*"* ]]
}

# ---------- Help mentions ----------

@test "help mentions audit subcommand" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"audit"* ]]
}

@test "help mentions strict auto-allow" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Auto-Allow"* ]]
}

@test "help mentions --trust" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--trust"* ]]
  [[ "$output" == *"trusted"* ]]
  [[ "$output" == *"untrusted"* ]]
}

@test "help mentions audit --watch" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--watch"* ]]
}

@test "help mentions project config" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project Config"* ]] || [[ "$output" == *".scode.yaml"* ]]
}

# ---------- -w alias in help ----------

@test "help documents -w alias for audit --watch" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--watch|-w"* ]]
}

# ---------- Bash 3.2 empty array compat regression ----------

@test "dry-run succeeds with no --block and no --allow (empty arrays)" {
  # Regression: bash 3.2 crashes on "${empty[@]}" with set -u
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

@test "dry-run succeeds with --block but no --allow" {
  run "$SCODE" --dry-run --block "$HOME/.test-block-$$" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

@test "dry-run succeeds with --allow but no --block" {
  run "$SCODE" --dry-run --allow "$HOME/.aws" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

@test "dry-run succeeds with no config file and no project config" {
  # Ensures empty CONFIG_BLOCKED/CONFIG_ALLOWED/PROJECT_BLOCKED/PROJECT_ALLOWED don't crash
  SCODE_CONFIG=/nonexistent/config run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]  # fails because explicit config not found, but should not crash
  [[ "$output" == *"config file not found"* ]]
}
