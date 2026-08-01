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

@test "runtime sandbox engine cannot be replaced through PATH" {
  require_any_runtime_sandbox
  local fake_bin="$TEST_PROJECT/fake-bin"
  mkdir -p "$fake_bin"
  printf '#!/bin/bash\nexit 99\n' > "$fake_bin/sandbox-exec"
  printf '#!/bin/bash\nexit 99\n' > "$fake_bin/bwrap"
  chmod +x "$fake_bin/sandbox-exec" "$fake_bin/bwrap"
  PATH="$fake_bin:$PATH" run "$SCODE" -C "$TEST_PROJECT" -- /usr/bin/true
  [ "$status" -eq 0 ]
}

@test "internal platform override is rejected for runtime execution" {
  _SCODE_PLATFORM=linux run "$SCODE" -C "$TEST_PROJECT" -- /usr/bin/true
  [ "$status" -eq 1 ]
  [[ "$output" == *"only permitted with --dry-run"* ]]
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

@test "rejects --allow path with tab control character" {
  local bad_path
  bad_path=$'/tmp/evil\tpath'
  run "$SCODE" --dry-run --allow "$bad_path" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid path"* ]]
}

@test "rejects empty --allow path" {
  run "$SCODE" --dry-run --allow "" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid path (empty)"* ]]
}

@test "rejects HOME root mount" {
  HOME=/ run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe HOME"* ]]
}

@test "synthetic HOME still protects the account home" {
  local fake_home="$TEST_PROJECT/synthetic-home"
  mkdir "$fake_home"
  HOME="$fake_home" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME"* ]]
}

@test "rejects invalid internal platform override" {
  _SCODE_PLATFORM=not-a-platform run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid internal platform override"* ]]
}

@test "relative command path resolves from --cwd" {
  local caller_dir
  caller_dir="$(mktemp -d)"
  track_cleanup "$caller_dir"
  printf '#!/bin/bash\necho caller\n' > "$caller_dir/tool"
  printf '#!/bin/bash\necho project\n' > "$TEST_PROJECT/tool"
  chmod +x "$caller_dir/tool" "$TEST_PROJECT/tool"
  local project_real
  project_real="$(realpath "$TEST_PROJECT")"

  run bash -c 'cd "$1" && "$2" --dry-run -C "$3" -- ./tool' _ "$caller_dir" "$SCODE" "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Command: ${project_real}/tool"* || "$output" == *"-- ${project_real}/tool"* ]]
  [[ "$output" != *"${caller_dir}/tool"* ]]
}

@test "runtime rejects shell builtins that are not executable files" {
  case "$(uname -s)" in
    Darwin) [[ -x /usr/bin/sandbox-exec ]] || skip "sandbox-exec unavailable" ;;
    Linux) [[ -x /usr/bin/bwrap ]] || skip "bubblewrap unavailable" ;;
    *) skip "unsupported platform" ;;
  esac

  run "$SCODE" -C "$TEST_PROJECT" -- source
  [ "$status" -eq 1 ]
  [[ "$output" == *"command not found: source"* ]]
}

# ---------- expand_path tilde safety ----------

@test "expand_path does not expand ~user form" {
  # ~root should NOT be expanded (we only expand ~/ and ~)
  run "$SCODE" --dry-run --block "~root" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_PROJECT/~root"* ]]
  [[ "$output" != *"/var/root"* ]]
}

# ---------- Block/allow hierarchy edge cases ----------

@test "--block / fails closed because it covers the project" {
  local config_file="$TEST_PROJECT/root-block-config.yaml"
  cat > "$config_file" <<'YAML'
allowed:
  - /tmp/scode-root-allow
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" --block / -C "$TEST_PROJECT" -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"custom block covers the project directory"* ]]
  done
}

@test "trailing slash on --block still suppresses descendant config allows" {
  local blocked_parent="${TEST_PROJECT}/slash-parent/"
  local blocked_parent_norm="${blocked_parent%/}"
  local allowed_child="${blocked_parent_norm}/child"
  local config_file="$TEST_PROJECT/trailing-block-config.yaml"
  cat > "$config_file" <<YAML
allowed:
  - ${allowed_child}
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" --block "$blocked_parent" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"${blocked_parent_norm}"* ]]
    [[ "$output" != *"${allowed_child}"* ]]
  done
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

@test "help lists current harness shortcuts" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"aider"* ]]
  [[ "$output" == *"cursor-agent"* ]]
  [[ "$output" == *"copilot"* ]]
  [[ "$output" == *"cn"* ]]
  [[ "$output" == *"kimi"* ]]
  [[ "$output" == *"kiro-cli"* ]]
  [[ "$output" == *"grok"* ]]
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
