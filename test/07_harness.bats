#!/usr/bin/env bats
# Harness detection, trust presets, audit

load test_helper

# ---------- Harness detection ----------

@test "detect_harness returns claude for direct command" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness returns codex for codex command" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+codex"* ]]
}

@test "detect_harness returns opencode for opencode command" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+opencode"* ]]
}

@test "detect_harness finds harness in wrapper command" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # e.g. /usr/bin/env claude
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /usr/bin/env claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness finds harness in shell wrapper command" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -lc "claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness finds harness after shell command separator" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -lc "cd /tmp && claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: shell wrapper does not match harness in arguments" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -lc "echo claude"
  [ "$status" -eq 0 ]
  [[ "$output" != *"strict+claude"* ]]
  [[ "$output" != *"$HOME/.claude"* ]]
}

@test "detect_harness: no harness detected for unknown command" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"strict+"* ]]
  [[ "$output" != *"auto-allowing"* ]]
}

@test "detect_harness: harness name in arguments does not trigger auto-allow" {
  # "echo claude" should NOT auto-allow ~/.claude
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- echo claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"auto-allowing"* ]]
  [[ "$output" != *"$HOME/.claude"* ]]
}

@test "detect_harness: env with KEY=VALUE before harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # "env FOO=bar claude" should detect claude
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env FOO=bar claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: env -u VAR before harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # "env -u DISPLAY claude" should detect claude
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env -u DISPLAY claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: env -- before harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: env KEY=VALUE does not match as harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # "env claude=yes true" — claude appears as assignment, not command
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env claude=yes true
  [ "$status" -eq 0 ]
  [[ "$output" != *"strict+claude"* ]]
}

@test "detect_harness: timeout duration before harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # "timeout 30 claude" — 30 is duration, not command
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- timeout 30 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: ionice -c class before harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # "ionice -c 2 claude" — -c takes a value arg
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- ionice -c 2 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: timeout with flags before harness" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # "timeout -k 5 30 claude" — -k takes value, 30 is duration
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- timeout -k 5 30 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: timeout --foreground claude (no duration positional)" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- timeout --foreground claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

# ---------- Harness config dir mapping ----------

@test "strict+claude auto-allows ~/.claude" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.claude"* ]]
  [[ "$output" == *"auto-allowing"* ]]
}

@test "strict+codex auto-allows ~/.codex" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.codex"* ]]
}

@test "strict+opencode auto-allows ~/.config/opencode" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.config/opencode"* ]]
  [[ "$output" == *"$HOME/.local/share/opencode"* ]]
}

@test "strict+goose auto-allows ~/.config/goose" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- goose
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.config/goose"* ]]
}

@test "strict+gemini auto-allows ~/.gemini" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- gemini
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.gemini"* ]]
}

# ---------- Strict + harness: profile content ----------

@test "strict+harness dry-run includes harness config dir in profile" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  # Harness state is visible but immutable in strict mode.
  [[ "$output" == *"Harness auto-allowed directories (read-only)"* ]]
  [[ "$output" == *"(subpath \"$HOME/.claude\")"* ]]
}

@test "strict+harness does not reopen macOS browser or Keychain data" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"(subpath \"$HOME/Library/Keychains\")"* ]]
  [[ "$output" != *"(subpath \"$HOME/Library/Application Support\")"* ]]
  [[ "$output" != *"(subpath \"$HOME/Library/Caches\")"* ]]
}

# ---------- Strict + harness: --block override ----------

@test "--block overrides harness auto-allow" {
  run "$SCODE" --dry-run --strict --block "$HOME/.claude" -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  # The auto-allow message should NOT include ~/.claude
  local info_line
  info_line=$(echo "$output" | grep "auto-allowing" || true)
  [[ "$info_line" != *"$HOME/.claude"* ]]
}

@test "config blocked suppresses harness auto-allow" {
  local cfg="$TEST_PROJECT/block-harness.yaml"
  printf 'blocked:\n  - ~/.claude\n' > "$cfg"
  run "$SCODE" --dry-run --strict --config "$cfg" -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  local info_line
  info_line=$(echo "$output" | grep "auto-allowing" || true)
  [[ "$info_line" != *"$HOME/.claude"* ]]
}

@test "project config blocked suppresses harness auto-allow" {
  printf 'blocked:\n  - ~/.claude\n' > "$TEST_PROJECT/.scode.yaml"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  local info_line
  info_line=$(echo "$output" | grep "auto-allowing" || true)
  [[ "$info_line" != *"$HOME/.claude"* ]]
  rm -f "$TEST_PROJECT/.scode.yaml"
}

# ---------- Strict + harness: Linux ----------

@test "linux strict+harness auto-allows harness config dir" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
  [[ "$output" == *"$HOME/.claude"* ]]
}

@test "linux strict+harness: no macOS Library carve-outs" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"Library/Application Support"* ]]
  [[ "$output" != *"Library/Keychains"* ]]
}

# ---------- Strict + non-harness: no auto-allow ----------

@test "strict without harness: no auto-allow" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- /usr/bin/true
  [ "$status" -eq 0 ]
  [[ "$output" != *"auto-allowing"* ]]
}

# ---------- Additional harness auto-allow coverage ----------

assert_strict_harness_paths() {
  local harness="$1"
  shift

  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+$harness"* ]]

  local expected_path
  for expected_path in "$@"; do
    [[ "$output" == *"$expected_path"* ]]
  done
}

@test "strict+droid auto-allows ~/.factory" {
  assert_strict_harness_paths droid "$HOME/.factory"
}

@test "strict+qwen auto-allows ~/.qwen" {
  assert_strict_harness_paths qwen "$HOME/.qwen"
}

@test "strict+codemux auto-allows current and legacy paths" {
  assert_strict_harness_paths codemux "$HOME/.codemux" "$HOME/.config/codemux"
}

@test "strict+pi auto-allows ~/.pi/agent" {
  assert_strict_harness_paths pi "$HOME/.pi/agent"
}

@test "strict+aider auto-allows config file and state directory" {
  assert_strict_harness_paths aider "$HOME/.aider" "$HOME/.aider.conf.yml"
}

@test "strict+amp auto-allows config and OAuth state" {
  assert_strict_harness_paths amp "$HOME/.config/amp" "$HOME/.amp"
}

@test "strict+crush auto-allows config and application state" {
  assert_strict_harness_paths crush "$HOME/.config/crush" "$HOME/.local/share/crush"
}

@test "strict+cursor-agent auto-allows ~/.cursor" {
  assert_strict_harness_paths cursor-agent "$HOME/.cursor"
}

@test "strict+copilot auto-allows config and Linux cache" {
  assert_strict_harness_paths copilot "$HOME/.copilot" "$HOME/.cache/copilot"
}

@test "strict+cn auto-allows ~/.continue" {
  assert_strict_harness_paths cn "$HOME/.continue"
}

@test "strict+kimi auto-allows current and legacy paths" {
  assert_strict_harness_paths kimi "$HOME/.kimi-code" "$HOME/.kimi"
}

@test "strict+openhands auto-allows ~/.openhands" {
  assert_strict_harness_paths openhands "$HOME/.openhands"
}

@test "strict+cline auto-allows ~/.cline" {
  assert_strict_harness_paths cline "$HOME/.cline"
}

@test "strict+kiro-cli auto-allows ~/.kiro" {
  assert_strict_harness_paths kiro-cli "$HOME/.kiro"
}

@test "strict+auggie auto-allows ~/.augment" {
  assert_strict_harness_paths auggie "$HOME/.augment"
}

@test "strict+grok auto-allows the default GROK_HOME" {
  assert_strict_harness_paths grok "$HOME/.grok"
}

@test "strict+grok does not auto-allow an environment-controlled GROK_HOME" {
  local custom_home="$TEST_PROJECT/custom-grok-home"
  mkdir -p "$custom_home"
  export GROK_HOME="$custom_home"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- grok
  [ "$status" -eq 0 ]
  local custom_home_real
  custom_home_real="$(realpath "$custom_home")"
  [[ "$output" != *"$custom_home_real"* ]]
  [[ "$output" == *"$HOME/.grok"* ]]
  unset GROK_HOME
}

# ---------- --trust presets ----------

@test "--trust untrusted enables strict + no-net + scrub-env + ro" {
  run "$SCODE" --trust untrusted --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # strict mode produces a deny-default profile
  assert_strict_mode_output "$output"
  # no-net: network should be denied
  [[ "$output" != *"(allow network"* ]]
  # ro: project dir should be read-only (file-read* not file-write*)
  assert_project_read_only_output "$output" "$TEST_PROJECT"
  # scrub-env active
  [[ "$output" == *"scrub-env active"* ]]
}

@test "--trust untrusted does not auto-open harness credentials" {
  run "$SCODE" --trust untrusted --dry-run -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"$HOME/.claude"* ]]
  [[ "$output" != *"auto-allowing"* ]]
}

@test "--trust trusted sets rw (default behavior)" {
  run "$SCODE" --trust trusted --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # trusted is default mode with rw; the project must be mounted writable
  assert_project_read_write_output "$output" "$TEST_PROJECT"
}

@test "--trust standard is same as no --trust" {
  run "$SCODE" --trust standard --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # Standard is default mode: non-strict, network on, project read-write.
  assert_non_strict_mode_output "$output"
  assert_network_enabled_output "$output"
  assert_project_read_write_output "$output" "$TEST_PROJECT"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    [[ "$output" == *"(allow default)"* ]]
  else
    [[ "$output" == *"bwrap"* ]]
  fi
  [[ "$output" != *"scrub-env active"* ]]
}

@test "--trust invalid level fails" {
  run "$SCODE" --trust banana --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown trust level"* ]]
}

@test "explicit --rw overrides --trust untrusted ro" {
  run "$SCODE" --trust untrusted --rw --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  assert_project_read_write_output "$output" "$TEST_PROJECT"
}

@test "--trust missing argument fails" {
  run "$SCODE" --trust
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--trust specified twice fails" {
  run "$SCODE" --trust trusted --trust untrusted --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"--trust specified more than once"* ]]
}



# ---------- --trust preset vs config interaction ----------

@test "--trust untrusted cannot be weakened by user config" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
net: on
strict: false
fs_mode: rw
scrub_env: false
YAML
  run "$SCODE" --trust untrusted --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # Trust preset should win: strict mode
  assert_strict_mode_output "$output"
  # Trust preset should win: no network
  [[ "$output" != *"(allow network"* ]]
  # Trust preset should win: read-only project
  assert_project_read_only_output "$output" "$TEST_PROJECT"
  rm -f "$user_config"
}

@test "--trust trusted overrides config strict and net off" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
strict: true
net: off
YAML
  run "$SCODE" --trust trusted --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # trusted should override config strict: allow-default, not deny-default
  assert_non_strict_mode_output "$output"
  # trusted should override config net: off — network should NOT be denied
  [[ "$output" != *"(deny network"* ]]
  rm -f "$user_config"
}

@test "--trust untrusted cannot be weakened by project config" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
net: on
strict: false
YAML
  run "$SCODE" --trust untrusted --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # Trust untrusted should still be strict
  assert_strict_mode_output "$output"
  # Trust untrusted should still deny network
  [[ "$output" != *"(allow network"* ]]
}

@test "--trust trusted prevents config scrub_env: true" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
scrub_env: true
YAML
  run "$SCODE" --trust trusted --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # trusted preset pins scrub_env=0 at CLI level, config cannot override
  [[ "$output" != *"--scrub-env active"* ]]
  rm -f "$user_config"
}

# ---------- Wrapper -- handling regression ----------

@test "detect_harness: env -- claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: nice -- claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- nice -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: nice with numeric priority" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- nice 10 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: nice -n 5 claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- nice -n 5 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: timeout -- claude detected" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- timeout -- 30 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
  [[ "$output" == *"$HOME/.claude"* ]]
}

@test "detect_harness: taskset -- mask claude detected" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- taskset -- 0x1 claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

# ---------- P1 regression: -p not a flag-with-value ----------

@test "detect_harness: command -p claude — -p is boolean" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- command -p claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: time -p claude — -p is boolean" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- time -p claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

# ---------- P1 regression: bash -c -- "cmd" ----------

@test "detect_harness: bash -c -- claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c -- "claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: env bash -c claude detected recursively" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- env FOO=bar bash -c "claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: nice bash -c claude detected recursively" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- nice bash -c "claude --version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: sh -c -- claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- sh -c -- "claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: bash -lc -- claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -lc -- "claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

# ---------- P2 regression: exec and assignment prefixes ----------

@test "detect_harness: exec claude detected via shell" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c "exec claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: FOO=bar claude detected" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c "FOO=bar claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: FOO=\"bar baz\" claude detected via shell" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c "FOO=\"bar baz\" claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: FOO=bar_baz (no spaces) claude detected via shell" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # Unquoted assignments without spaces work with simple word splitting
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c "FOO=bar_baz claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: exec FOO=bar claude detected via shell" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c "exec FOO=bar claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}

@test "detect_harness: multiple assignments before claude" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- bash -c "A=1 B=2 claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+claude"* ]]
}
