#!/usr/bin/env bats
# Configuration system — parsing, validation, precedence

load test_helper

# ---------- Config file ----------

@test "synthetic HOME cannot redirect the default config path" {
  local config_dir="$TEST_PROJECT/.config/scode"
  mkdir -p "$config_dir"
  cat > "$config_dir/sandbox.yaml" <<'YAML'
blocked:
  - /tmp/config-blocked-test
YAML
  HOME="$TEST_PROJECT" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"/tmp/config-blocked-test"* ]]
}

@test "--config loads a specific config file" {
  local config_file="$TEST_PROJECT/custom-config.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/custom-config-test
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/custom-config-test"* ]]
}

@test "SCODE_CONFIG env var loads a specific config file" {
  local config_file="$TEST_PROJECT/env-config.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/env-config-test
YAML
  SCODE_CONFIG="$config_file" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/env-config-test"* ]]
}

@test "SCODE_CONFIG supports literal tilde path" {
  local fake_home="$TEST_PROJECT/fake-home"
  local config_dir="$fake_home/.config/scode"
  mkdir -p "$config_dir"
  cat > "$config_dir/sandbox.yaml" <<'YAML'
net: off
YAML
  local platform
  for platform in darwin linux; do
    HOME="$fake_home" SCODE_CONFIG='~/.config/scode/sandbox.yaml' _SCODE_PLATFORM="$platform" \
      run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
  done
}

@test "--config overrides SCODE_CONFIG env var" {
  local env_config="$TEST_PROJECT/env.yaml"
  local cli_config="$TEST_PROJECT/cli.yaml"
  cat > "$env_config" <<'YAML'
blocked:
  - /tmp/from-env
YAML
  cat > "$cli_config" <<'YAML'
blocked:
  - /tmp/from-cli
YAML
  SCODE_CONFIG="$env_config" run "$SCODE" --dry-run --config "$cli_config" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/from-cli"* ]]
  [[ "$output" != *"/tmp/from-env"* ]]
}

@test "--config with nonexistent file errors" {
  run "$SCODE" --config /nonexistent/config.yaml --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "--config without argument fails" {
  run "$SCODE" --config
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--config specified twice fails" {
  local config_a="$TEST_PROJECT/config-a.yaml"
  local config_b="$TEST_PROJECT/config-b.yaml"
  cat > "$config_a" <<'YAML'
net: off
YAML
  cat > "$config_b" <<'YAML'
net: on
YAML
  run "$SCODE" --dry-run --config "$config_a" --config "$config_b" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"--config specified more than once"* ]]
}

@test "config allowed: overrides blocked dir in profile" {
  local config_file="$TEST_PROJECT/allowed-config.yaml"
  cat > "$config_file" <<'YAML'
allowed:
  - ~/Documents
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    # Documents is blocked by default but allowed by config — should not be blocked.
    [[ "$output" != *"$HOME/Documents"* ]]
  done
}

@test "CLI --block overrides config allowed for same path" {
  local config_file="$TEST_PROJECT/allow-then-block.yaml"
  cat > "$config_file" <<'YAML'
allowed:
  - /tmp/scode-allow-then-block
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" --block /tmp/scode-allow-then-block -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/scode-allow-then-block"* ]]
  done
}

@test "CLI --block parent overrides config allowed child path" {
  local policy_dir="$TEST_PROJECT/policy"
  local blocked_parent="$policy_dir/parent"
  local allowed_child="$blocked_parent/child"
  mkdir -p "$allowed_child"

  local config_file="$TEST_PROJECT/allow-child.yaml"
  cat > "$config_file" <<YAML
allowed:
  - $allowed_child
YAML

  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" --block "$blocked_parent" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"$blocked_parent"* ]]
    [[ "$output" != *"$allowed_child"* ]]
  done
}

# ---------- Config scalar flags ----------

@test "config net: off disables network" {
  local config_file="$TEST_PROJECT/net-off.yaml"
  cat > "$config_file" <<'YAML'
net: off
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
  done
}

@test "config fs_mode: ro makes project read-only" {
  local config_file="$TEST_PROJECT/fs-ro.yaml"
  cat > "$config_file" <<'YAML'
fs_mode: ro
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_project_read_only_output "$output" "$TEST_PROJECT"
  done
}

@test "config strict: true enables strict mode" {
  local config_file="$TEST_PROJECT/strict.yaml"
  cat > "$config_file" <<'YAML'
strict: true
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_strict_mode_output "$output"
  done
}

@test "config scrub_env: true scrubs env vars" {
  local config_file="$TEST_PROJECT/scrub.yaml"
  cat > "$config_file" <<'YAML'
scrub_env: true
YAML
  export OPENAI_API_KEY="config-test-key"
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scrubbed env vars"* ]]
  [[ "$output" == *"OPENAI_API_KEY"* ]]
  unset OPENAI_API_KEY
}

@test "config grok_defense: true enables strict Grok containment" {
  local config_file="$TEST_PROJECT/grok-defense.yaml"
  cat > "$config_file" <<'YAML'
grok_defense: true
YAML

  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- grok
  [ "$status" -eq 0 ]
  assert_strict_mode_output "$output"
  [[ "$output" == *"grok defense:"* ]]
  [[ "$output" == *"$TEST_PROJECT/.git"* ]]
  [[ "$output" == *"$TEST_PROJECT/.env"* ]]
  [[ "$output" == *"grok_defense active"* ]]
  [[ "$output" == *"--scrub-env active"* ]]
}

@test "config grok_defense: false leaves standard mode unchanged" {
  local config_file="$TEST_PROJECT/grok-defense-off.yaml"
  cat > "$config_file" <<'YAML'
grok_defense: false
YAML

  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- grok
  [ "$status" -eq 0 ]
  assert_non_strict_mode_output "$output"
  [[ "$output" != *"grok_defense active"* ]]
}

@test "config rejects invalid grok_defense value" {
  local config_file="$TEST_PROJECT/grok-defense-invalid.yaml"
  cat > "$config_file" <<'YAML'
grok_defense: maybe
YAML

  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- grok
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid config: grok_defense: maybe"* ]]
}

@test "project config may enable but not disable grok defense" {
  local user_config="$TEST_PROJECT/user-grok-defense.yaml"
  cat > "$user_config" <<'YAML'
grok_defense: true
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
grok_defense: false
YAML

  run "$SCODE" --dry-run --config "$user_config" -C "$TEST_PROJECT" -- grok
  [ "$status" -eq 0 ]
  assert_strict_mode_output "$output"
  [[ "$output" == *"ignoring permissive project config value: grok_defense: false"* ]]
}

@test "grok defense refuses HOME as the project" {
  local config_file="$TEST_PROJECT/grok-home-defense.yaml"
  cat > "$config_file" <<'YAML'
grok_defense: true
YAML

  HOME="$TEST_PROJECT" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- grok
  [ "$status" -eq 1 ]
  [[ "$output" == *"grok_defense refuses a project rooted at"* ]]
}

@test "config accepts quoted scalar values" {
  local config_file="$TEST_PROJECT/quoted-scalars.yaml"
  cat > "$config_file" <<'YAML'
net: "off"
fs_mode: "ro"
strict: "true"
scrub_env: "true"
YAML
  export OPENAI_API_KEY="quoted-scalar-test"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_strict_mode_output "$output"
    assert_network_disabled_output "$output"
    [[ "$output" == *"scrubbed env vars"* ]]
    [[ "$output" == *"OPENAI_API_KEY"* ]]
  done
  unset OPENAI_API_KEY
}

@test "config accepts quoted scalar values with trailing inline comments" {
  local config_file="$TEST_PROJECT/quoted-scalars-inline-comment.yaml"
  cat > "$config_file" <<'YAML'
net: "off" # disable network
fs_mode: "ro" # read-only project
strict: "true" # strict mode
scrub_env: "true" # scrub secrets
YAML
  export OPENAI_API_KEY="quoted-scalar-inline-comment-test"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_strict_mode_output "$output"
    assert_network_disabled_output "$output"
    [[ "$output" == *"scrubbed env vars"* ]]
    [[ "$output" == *"OPENAI_API_KEY"* ]]
  done
  unset OPENAI_API_KEY
}

@test "config accepts quoted list paths" {
  local config_file="$TEST_PROJECT/quoted-list-paths.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - "/tmp/quoted-block"
allowed:
  - "~/Documents/projects"
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/quoted-block"* ]]
  [[ "$output" == *"$HOME/Documents/projects"* ]]
}

@test "config accepts quoted list paths with trailing inline comments" {
  local config_file="$TEST_PROJECT/quoted-list-inline-comment.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - "/tmp/path with # hash" # blocked list entry
allowed:
  - "~/Documents/projects" # allowed list entry
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/path with # hash"* ]]
  [[ "$output" == *"$HOME/Documents/projects"* ]]
  [[ "$output" != *"blocked list entry"* ]]
  [[ "$output" != *"allowed list entry"* ]]
}

@test "CLI --no-net overrides config net: on" {
  local config_file="$TEST_PROJECT/net-on.yaml"
  cat > "$config_file" <<'YAML'
net: on
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --no-net --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
  done
}

@test "CLI --rw overrides config fs_mode: ro" {
  local config_file="$TEST_PROJECT/fs-ro-override.yaml"
  cat > "$config_file" <<'YAML'
fs_mode: ro
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --rw --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_project_read_write_output "$output" "$TEST_PROJECT"
  done
}

@test "config scalars combined with blocked/allowed" {
  local config_file="$TEST_PROJECT/combined.yaml"
  cat > "$config_file" <<'YAML'
strict: true
scrub_env: true
blocked:
  - /tmp/combo-block
YAML
  export OPENAI_API_KEY="combo-test-key"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_strict_mode_output "$output"
    [[ "$output" == *"scrubbed env vars"* ]]
  done
  unset OPENAI_API_KEY
}

# ---------- Config parser: scalar ordering ----------

@test "config scalars after list section are parsed" {
  local config_file="$TEST_PROJECT/scalar-after-list.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/ordering-test
net: off
fs_mode: ro
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
    assert_project_read_only_output "$output" "$TEST_PROJECT"
    [[ "$output" == *"/tmp/ordering-test"* ]]
  done
}

@test "config scalars before list section are parsed" {
  local config_file="$TEST_PROJECT/scalar-before-list.yaml"
  cat > "$config_file" <<'YAML'
net: off
blocked:
  - /tmp/before-test
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
    [[ "$output" == *"/tmp/before-test"* ]]
  done
}

# ---------- Config value validation ----------

@test "config rejects invalid net value" {
  local config_file="$TEST_PROJECT/bad-net.yaml"
  cat > "$config_file" <<'YAML'
net: maybe
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid config"* ]]
  [[ "$output" == *"net"* ]]
}

@test "config rejects invalid fs_mode value" {
  local config_file="$TEST_PROJECT/bad-fs.yaml"
  cat > "$config_file" <<'YAML'
fs_mode: readonly
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid config"* ]]
  [[ "$output" == *"fs_mode"* ]]
}

@test "config rejects unknown scalar key" {
  local config_file="$TEST_PROJECT/unknown-key.yaml"
  cat > "$config_file" <<'YAML'
nett: off
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown key"* ]]
  [[ "$output" == *"nett"* ]]
}

@test "config rejects unknown section" {
  local config_file="$TEST_PROJECT/unknown-section.yaml"
  cat > "$config_file" <<'YAML'
secrets:
  - ~/.ssh
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown section"* ]]
  [[ "$output" == *"secrets"* ]]
}

@test "config rejects list item outside section" {
  local config_file="$TEST_PROJECT/list-outside-section.yaml"
  cat > "$config_file" <<'YAML'
- ~/.ssh
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"list item outside a section"* ]]
}

@test "config rejects comment-only list item" {
  local config_file="$TEST_PROJECT/comment-only-item.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  -   # comment only
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty list item"* ]]
}

@test "config duplicate strict keys use last value" {
  local config_file="$TEST_PROJECT/duplicate-strict.yaml"
  cat > "$config_file" <<'YAML'
strict: true
strict: false
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_non_strict_mode_output "$output"
  done
}

@test "config strips inline comments from values" {
  local config_file="$TEST_PROJECT/inline-comment.yaml"
  cat > "$config_file" <<'YAML'
fs_mode: ro # make read-only
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_project_read_only_output "$output" "$TEST_PROJECT"
  done
}

@test "SCODE_NET rejects invalid value" {
  SCODE_NET=garbage run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid SCODE_NET"* ]]
}

@test "SCODE_FS_MODE rejects invalid value" {
  SCODE_FS_MODE=garbage run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid SCODE_FS_MODE"* ]]
}

# ---------- Config CRLF handling ----------

@test "config handles CRLF line endings" {
  local config_file="$TEST_PROJECT/crlf-config.yaml"
  printf 'net: off\r\nfs_mode: ro\r\n' > "$config_file"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
    assert_project_read_only_output "$output" "$TEST_PROJECT"
  done
}

# ---------- Config: strict false / scrub_env false ----------

@test "config strict: false does not enable strict mode" {
  local config_file="$TEST_PROJECT/strict-false.yaml"
  cat > "$config_file" <<'YAML'
strict: false
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_non_strict_mode_output "$output"
  done
}

@test "config scrub_env: false does not scrub" {
  local config_file="$TEST_PROJECT/scrub-false.yaml"
  cat > "$config_file" <<'YAML'
scrub_env: false
YAML
  export OPENAI_API_KEY="should-not-scrub"
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"scrubbed env vars"* ]]
  unset OPENAI_API_KEY
}

# ---------- Config: empty file ----------

@test "config empty file does not error" {
  local config_file="$TEST_PROJECT/empty.yaml"
  touch "$config_file"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_dry_run_generated "$output"
  done
}

# ---------- Config: inline comments on list items ----------

@test "config rejects inline comments on unquoted list items" {
  local config_file="$TEST_PROJECT/list-comment.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/list-item-test # this is a comment
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"unquoted list item contains ' #'"* ]]
}

@test "config preserves hash in quoted list paths" {
  local config_file="$TEST_PROJECT/quoted-hash-list.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - "/tmp/path with # hash"
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/path with # hash"* ]]
}

@test "config preserves hash in single-quoted list paths" {
  local config_file="$TEST_PROJECT/single-quoted-hash-list.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - '/tmp/path with # hash'
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/path with # hash"* ]]
}

@test "config accepts YAML escaped single quotes ('it''s-data')" {
  local config_file="$TEST_PROJECT/yaml-sq-escape.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - '/tmp/it''s-data'
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/it's-data"* ]]
}

@test "config plain single-quoted value still works" {
  local config_file="$TEST_PROJECT/yaml-sq-plain.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - '/tmp/plain-single-quoted'
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/plain-single-quoted"* ]]
}

# ---------- Per-project .scode.yaml ----------

@test "project .scode.yaml blocked paths are applied" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
blocked:
  - /tmp/scode-test-project-blocked
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/scode-test-project-blocked"* ]]
}

@test "project .scode.yaml allowed paths are ignored unless user-authorized" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~/Documents
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  local docs_expanded="$HOME/Documents"
  [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
  [[ "$output" == *"(subpath \"$docs_expanded\")"* || "$output" == *"--tmpfs $docs_expanded"* ]]
}

@test "CLI --block parent overrides project allowed child path" {
  local policy_dir="$TEST_PROJECT/policy-project"
  local blocked_parent="$policy_dir/parent"
  local allowed_child="$blocked_parent/child"
  mkdir -p "$allowed_child"

  cat > "$TEST_PROJECT/.scode.yaml" <<YAML
allowed:
  - $allowed_child
YAML

  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --block "$blocked_parent" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"$blocked_parent"* ]]
    [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
    local policy_output
    policy_output="$(printf '%s\n' "$output" | sed '/ignoring project config/d')"
    [[ "$policy_output" != *"$allowed_child"* ]]
  done
}

@test "user config overrides project config" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
net: off
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
net: on
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
    [ "$status" -eq 0 ]
    # User config net: off wins over project config net: on.
    assert_network_disabled_output "$output"
  done
  rm -f "$user_config"
}

@test "user config strict: false overrides project config strict: true" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
strict: false
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
strict: true
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
    [ "$status" -eq 0 ]
    # User config strict: false should win — no deny-default.
    assert_non_strict_mode_output "$output"
  done
  rm -f "$user_config"
}

@test "user config scrub_env: false overrides project config scrub_env: true" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
scrub_env: false
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
scrub_env: true
YAML
  run "$SCODE" --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # User config scrub_env: false should win — no scrubbing message
  [[ "$output" != *"scrubbed env vars"* ]]
  rm -f "$user_config"
}

@test "project .scode.yaml strict is applied" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
strict: true
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
    [ "$status" -eq 0 ]
    assert_strict_mode_output "$output"
  done
}

@test "missing project .scode.yaml is fine" {
  # No .scode.yaml in TEST_PROJECT — should work normally
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
}

# ---------- Project config unblock warnings ----------

@test "project config ignores allowed default-protected path" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~/Documents
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
  [[ "$output" == *"Documents"* ]]
  [[ "$output" == *"$HOME/Documents"* ]]
}

@test "project config ignores allowed subpath of default-protected path" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~/Documents/projects
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
  [[ "$output" == *"Documents/projects"* ]]
}

@test "project config cannot allow HOME parent of default-protected paths" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
    [[ "$output" == *"$HOME/.aws"* ]]
    [[ "$output" == *"$HOME/.gnupg"* ]]
  done
}

@test "project config ignores non-default allowed path" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - /tmp/some-harmless-path
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
}

@test "project config allowed dot cannot weaken --trust untrusted read-only project" {
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - .
YAML
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --trust untrusted --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"ignoring project config (.scode.yaml) allowed path"* ]]
    assert_project_read_only_output "$output" "$TEST_PROJECT"
  done
}

# ---------- Config array merging ----------

@test "user config and project config blocked arrays combine" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
blocked:
  - /tmp/scode-user-blocked-path
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
blocked:
  - /tmp/scode-project-blocked-path
YAML
  run "$SCODE" --config "$user_config" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # Both paths should appear in the profile
  [[ "$output" == *"/tmp/scode-user-blocked-path"* ]]
  [[ "$output" == *"/tmp/scode-project-blocked-path"* ]]
  rm -f "$user_config"
}

# ---------- P3: SCODE_CONFIG pointing to missing file ----------

@test "SCODE_CONFIG with nonexistent file errors" {
  SCODE_CONFIG="/nonexistent/config-$$.yaml" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"config file not found"* ]]
}

# ---------- Project config security warning regression ----------

@test "project config warns when enabling network" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
net: on
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring permissive project config value: net: on"* ]]
}

@test "project config warns when disabling strict (if user config enables it)" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
strict: true
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
strict: false
YAML
  run "$SCODE" --dry-run --config "$user_config" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring permissive project config value: strict: false"* ]]
  rm -f "$user_config"
}

@test "project config warns when disabling scrub_env (if user config enables it)" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
scrub_env: true
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
scrub_env: false
YAML
  run "$SCODE" --dry-run --config "$user_config" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring permissive project config value: scrub_env: false"* ]]
  rm -f "$user_config"
}

@test "project config no warning when net: on matches user config" {
  mkdir -p "$TEST_PROJECT"
  local user_config
  user_config="$(mktemp)"
  cat > "$user_config" <<'YAML'
net: on
YAML
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
net: on
YAML
  run "$SCODE" --dry-run --config "$user_config" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"enables network access"* ]]
  rm -f "$user_config"
}

@test "project config fs_mode rw cannot weaken SCODE_FS_MODE ro" {
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
fs_mode: rw
YAML
  SCODE_FS_MODE=ro run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring permissive project config value: fs_mode: rw"* ]]
  assert_project_read_only_output "$output" "$TEST_PROJECT"
}

# ---------- YAML parser edge cases ----------

@test "config: double-quoted value with backslash" {
  local config_file="$TEST_PROJECT/dq-backslash.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - "/path/with backslash \\ here"
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # parse_yaml_value preserves raw \\ from double-quoted string;
  # sandbox profile then escapes each \ as \\, yielding 4 backslashes in output
  [[ "$output" == *'backslash \\\\ here'* ]]
}

@test "config: empty double-quoted value" {
  local config_file="$TEST_PROJECT/empty-dq.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - ""
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty list item"* ]]
}

@test "config: empty single-quoted value" {
  local config_file="$TEST_PROJECT/empty-sq.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - ''
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty list item"* ]]
}

@test "config: bare key with no value (empty)" {
  local config_file="$TEST_PROJECT/bare-key.yaml"
  printf 'net:\n' > "$config_file"
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  # bare "net:" without value is parsed as a section header;
  # net is not a valid section (only blocked/allowed), so it errors
  [[ "$output" == *"unknown section"* ]]
  [[ "$output" == *"net"* ]]
}

@test "config: unquoted path with spaces" {
  local config_file="$TEST_PROJECT/unquoted-spaces.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /path/with spaces/dir
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/path/with spaces/dir"* ]]
}

@test "config rejects unquoted list item containing literal space-hash fragment" {
  local config_file="$TEST_PROJECT/unquoted-hash-fragment.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/project #3
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"unquoted list item contains ' #'"* ]]
}

@test "config: unquoted tilde path" {
  local config_file="$TEST_PROJECT/tilde-path.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - ~/custom-dir
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/custom-dir"* ]]
}

@test "config: double-quoted value with colon" {
  local config_file="$TEST_PROJECT/dq-colon.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - "colon:value"
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"colon:value"* ]]
}

@test "config: single-quoted value with colon" {
  local config_file="$TEST_PROJECT/sq-colon.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - 'colon:value'
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"colon:value"* ]]
}

@test "config: boolean true/on/yes — only true accepted for strict" {
  # strict only accepts true/false; on/yes are rejected
  local config_file="$TEST_PROJECT/strict-true-ok.yaml"
  printf 'strict: true\n' > "$config_file"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_strict_mode_output "$output"
  done
  # on / yes should be rejected
  for v in on yes; do
    local bad_file="$TEST_PROJECT/strict-${v}.yaml"
    printf 'strict: %s\n' "$v" > "$bad_file"
    run "$SCODE" --dry-run --config "$bad_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid config"* ]]
    [[ "$output" == *"strict"* ]]
  done
}

@test "config: boolean false/off/no — only false accepted for strict" {
  # strict only accepts true/false; off/no are rejected
  local config_file="$TEST_PROJECT/strict-false-ok.yaml"
  printf 'strict: false\n' > "$config_file"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_non_strict_mode_output "$output"
  done
  # off / no should be rejected
  for v in off no; do
    local bad_file="$TEST_PROJECT/strict-${v}.yaml"
    printf 'strict: %s\n' "$v" > "$bad_file"
    run "$SCODE" --dry-run --config "$bad_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid config"* ]]
    [[ "$output" == *"strict"* ]]
  done
}

@test "config: blocked and allowed lists with mixed quoting styles" {
  local config_file="$TEST_PROJECT/mixed-quoting.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/unquoted-block
  - "/tmp/double-quoted-block"
  - '/tmp/single-quoted-block'
allowed:
  - /tmp/unquoted-allow
  - "/tmp/double-quoted-allow"
  - '/tmp/single-quoted-allow'
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/unquoted-block"* ]]
  [[ "$output" == *"/tmp/double-quoted-block"* ]]
  [[ "$output" == *"/tmp/single-quoted-block"* ]]
}

@test "config: CRLF line endings with lists" {
  local config_file="$TEST_PROJECT/crlf-list.yaml"
  printf 'blocked:\r\n  - /tmp/crlf-item\r\nnet: off\r\n' > "$config_file"
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/crlf-item"* ]]
    assert_network_disabled_output "$output"
  done
}

@test "project config symbolic link is rejected before parsing" {
  local nested_project="$TEST_PROJECT/symlink-project"
  local outside_config="$TEST_PROJECT/outside-project-config.yaml"
  mkdir -p "$nested_project"
  printf 'strict: true\n' > "$outside_config"
  ln -s "$outside_config" "$nested_project/.scode.yaml"

  run "$SCODE" --dry-run -C "$nested_project" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing symbolic-link project config"* ]]
}

@test "project config hard link is rejected" {
  local nested_project="$TEST_PROJECT/hardlink-project"
  local outside_config="$TEST_PROJECT/outside-hardlink-config.yaml"
  mkdir -p "$nested_project"
  printf 'strict: true\n' > "$outside_config"
  ln "$outside_config" "$nested_project/.scode.yaml"

  run "$SCODE" --dry-run -C "$nested_project" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing unsafe project config"* ]]
}

@test "config files larger than one MiB are rejected" {
  local config_file="$TEST_PROJECT/oversized-config.yaml"
  dd if=/dev/zero of="$config_file" bs=1048577 count=1 2>/dev/null

  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"config file exceeds 1048576 bytes"* ]]
}

@test "grok defense rejects an allow that reopens mandatory blocks" {
  local config_file="$TEST_PROJECT/grok-defense-overlap.yaml"
  cat > "$config_file" <<YAML
grok_defense: true
allowed:
  - $TEST_PROJECT
YAML

  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- grok
  [ "$status" -ne 0 ]
  [[ "$output" == *"grok_defense conflicts with allowed path"* ]]
}
