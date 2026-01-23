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
  # Profile should have an allow rule for the harness config dir
  [[ "$output" == *"(allow file-read* file-write*"* ]]
  [[ "$output" == *"(subpath \"$HOME/.claude\")"* ]]
}

@test "strict+harness dry-run includes RO Library carve-outs on macOS" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  # Read-only carve-out for Keychains
  [[ "$output" == *"Harness auto-allowed directories (read-only)"* ]]
  [[ "$output" == *"(subpath \"$HOME/Library/Keychains\")"* ]]
  # RW carve-outs for Application Support, Caches, etc.
  [[ "$output" == *"(subpath \"$HOME/Library/Application Support\")"* ]]
  [[ "$output" == *"(subpath \"$HOME/Library/Caches\")"* ]]
}

@test "strict+harness: Keychains is file-read* only (not file-write*)" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  # Extract the RO section
  local ro_section
  ro_section=$(echo "$output" | sed -n '/Harness auto-allowed.*read-only/,/^$/p')
  [[ "$ro_section" == *"(allow file-read*"* ]]
  [[ "$ro_section" != *"file-write*"* ]]
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

@test "--block specific Library dir suppresses that auto-allow" {
  run "$SCODE" --dry-run --strict --block "$HOME/Library/Keychains" -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  local info_line
  info_line=$(echo "$output" | grep "auto-allowing" || true)
  [[ "$info_line" != *"Keychains"* ]]
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

@test "strict+droid auto-allows ~/.droid" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- droid
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.droid"* ]]
}

@test "strict+qwen auto-allows ~/.config/qwen" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- qwen
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.config/qwen"* ]]
}

@test "strict+codemux auto-allows ~/.config/codemux" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- codemux
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.config/codemux"* ]]
}

@test "strict+pi auto-allows ~/.config/pi" {
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- pi
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.config/pi"* ]]
}

# ---------- --trust presets ----------

@test "--trust untrusted enables strict + no-net + scrub-env + ro" {
  run "$SCODE" --trust untrusted --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # strict mode produces a deny-default profile
  [[ "$output" == *"deny default"* ]]
  # no-net: network should be denied
  [[ "$output" != *"(allow network"* ]]
  # ro: project dir should be read-only (file-read* not file-write*)
  [[ "$output" == *"Project directory (read-only)"* ]]
  # scrub-env active
  [[ "$output" == *"scrub-env active"* ]]
}

@test "--trust trusted sets rw (default behavior)" {
  run "$SCODE" --trust trusted --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # trusted is default mode with rw; profile should contain file-write
  [[ "$output" == *"file-write"* ]]
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
  [[ "$output" == *"file-write"* ]]
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
  [[ "$output" == *"deny default"* ]]
  # Trust preset should win: no network
  [[ "$output" != *"(allow network"* ]]
  # Trust preset should win: read-only project
  [[ "$output" == *"Project directory (read-only)"* ]]
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
  # trusted should override config strict: profile should use allow-default, not deny-default
  [[ "$output" == *"(allow default)"* ]]
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
  [[ "$output" == *"deny default"* ]]
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
