#!/usr/bin/env bats
# Configuration system — parsing, validation, precedence

load test_helper

# ---------- Config file ----------

@test "config file adds blocked dirs (default path)" {
  local config_dir="$TEST_PROJECT/.config/scode"
  mkdir -p "$config_dir"
  cat > "$config_dir/sandbox.yaml" <<'YAML'
blocked:
  - /tmp/config-blocked-test
YAML
  HOME="$TEST_PROJECT" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/config-blocked-test"* ]]
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

@test "config strips inline comments from list items" {
  local config_file="$TEST_PROJECT/list-comment.yaml"
  cat > "$config_file" <<'YAML'
blocked:
  - /tmp/list-item-test # this is a comment
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/list-item-test"* ]]
  # The comment text should NOT appear in the profile
  [[ "$output" != *"this is a comment"* ]]
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

@test "project .scode.yaml allowed paths are applied" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~/Documents
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  # ~/Documents is default blocked; project allow should override it.
  # In default mode, blocked dirs are emitted as deny rules. Documents
  # should NOT appear in any deny rule.
  local docs_expanded="$HOME/Documents"
  [[ "$output" != *"(deny"*"$docs_expanded"* ]]
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
    [[ "$output" != *"$allowed_child"* ]]
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

@test "project config warns when unblocking default-protected path" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~/Documents
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"project config (.scode.yaml) unblocks default-protected path"* ]]
  [[ "$output" == *"Documents"* ]]
}

@test "project config warns when unblocking subpath of default-protected path" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - ~/Documents/projects
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"project config (.scode.yaml) unblocks default-protected path"* ]]
  [[ "$output" == *"Documents/projects"* ]]
}

@test "project config does not warn for non-default allowed path" {
  mkdir -p "$TEST_PROJECT"
  cat > "$TEST_PROJECT/.scode.yaml" <<'YAML'
allowed:
  - /tmp/some-harmless-path
YAML
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" != *"unblocks default-protected path"* ]]
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
  [[ "$output" == *"enables network access"* ]]
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
  [[ "$output" == *"disables strict mode"* ]]
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
  [[ "$output" == *"disables env scrubbing"* ]]
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
