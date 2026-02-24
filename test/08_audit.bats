#!/usr/bin/env bats
# Audit subcommand and logging

load test_helper

stop_watch_process() {
  local pid="$1"
  # Kill children first to avoid lingering `tail -f` processes.
  if command -v pgrep >/dev/null 2>&1; then
    local child_pids
    child_pids="$(pgrep -P "$pid" 2>/dev/null || true)"
    for cpid in $child_pids; do
      local grandchild_pids
      grandchild_pids="$(pgrep -P "$cpid" 2>/dev/null || true)"
      for gpid in $grandchild_pids; do
        kill "$gpid" 2>/dev/null || true
      done
      kill "$cpid" 2>/dev/null || true
    done
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# ---------- Log file ----------

@test "--log creates log file with session header" {
  require_runtime_sandbox
  local log_file="$TEST_PROJECT/test-session.log"
  run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  grep -q "scode session" "$log_file"
  grep -q "command: true" "$log_file"
  # realpath may resolve /var -> /private/var on macOS
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  grep -q "cwd: ${real_project}" "$log_file"
}

@test "--log includes sandbox profile" {
  require_runtime_sandbox
  local log_file="$TEST_PROJECT/test-profile.log"
  run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  grep -q "profile:" "$log_file"
}

@test "--log creates missing parent directories" {
  require_runtime_sandbox
  local log_file="$TEST_PROJECT/nested/logs/session.log"
  run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
}

# ---------- Log file on Linux ----------

@test "linux dry-run: --log with fake bwrap writes log file" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local fake_bwrap="$fake_bin/bwrap"
  local log_file="$TEST_PROJECT/linux-log.log"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"

  mkdir -p "$fake_bin"
  cat > "$fake_bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    exec "$@"
  fi
  shift
done
echo "missing -- separator" >&2
exit 2
EOF
  chmod +x "$fake_bwrap"

  PATH="$fake_bin:$PATH" _SCODE_PLATFORM=linux run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  grep -q "scode session" "$log_file"
  grep -q "command: true" "$log_file"
}

@test "linux runtime: --log creates missing parent directories" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local fake_bwrap="$fake_bin/bwrap"
  local log_file="$TEST_PROJECT/nested/linux/logs/session.log"

  mkdir -p "$fake_bin"
  cat > "$fake_bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    exec "$@"
  fi
  shift
done
echo "missing -- separator" >&2
exit 2
EOF
  chmod +x "$fake_bwrap"

  PATH="$fake_bin:$PATH" _SCODE_PLATFORM=linux run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
}

# ---------- --log tilde expansion ----------

@test "--log expands tilde in path" {
  local fake_home="$TEST_PROJECT/log-home"
  mkdir -p "$fake_home"
  # --log ~/test.log should expand ~ to fake_home
  HOME="$fake_home" run "$SCODE" --dry-run --log "~/test.log" -C "$TEST_PROJECT" -- true
  # Dry-run doesn't write logs, but the path should resolve without error
  [ "$status" -eq 0 ]
}

# ---------- Log header includes allowed paths ----------

@test "dry-run: log header mentions allowed paths" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local allow_dir="$TEST_PROJECT/log-header-allow"
  mkdir -p "$allow_dir"
  local log_file
  log_file="$(mktemp)"
  run "$SCODE" --dry-run --allow "$allow_dir" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # The dry-run output with --log should mention allowed paths in its profile
  [[ "$output" == *"${allow_dir}"* ]] || [[ -f "$log_file" ]]
  rm -f "$log_file"
}

@test "linux runtime: --log records allowed metadata entries" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local fake_bwrap="$fake_bin/bwrap"
  local allow_dir="$TEST_PROJECT/allowed-runtime"
  local log_file="$TEST_PROJECT/log-with-allowed.log"

  mkdir -p "$fake_bin" "$allow_dir"
  cat > "$fake_bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    exec "$@"
  fi
  shift
done
echo "missing -- separator" >&2
exit 2
EOF
  chmod +x "$fake_bwrap"

  PATH="$fake_bin:$PATH" _SCODE_PLATFORM=linux run "$SCODE" --log "$log_file" --allow "$allow_dir" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  local real_allow
  real_allow="$(realpath "$allow_dir")"
  run grep "^# allowed: ${real_allow}$" "$log_file"
  [ "$status" -eq 0 ]
}

# ---------- P3: logging stderr capture ----------

@test "--log captures stderr from sandboxed command" {
  require_runtime_sandbox
  local log_file="$TEST_PROJECT/stderr-test.log"
  # Run a command that writes to stderr
  run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- bash -c 'echo "scode-stderr-marker" >&2'
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  # The stderr output should be captured in the log file
  grep -q "scode-stderr-marker" "$log_file"
}

# ---------- Audit subcommand ----------

@test "audit parses macOS deny patterns" {
  local log_file="$TEST_PROJECT/audit-macos.log"
  cat > "$log_file" <<EOF
deny(file-read-data) $HOME/Documents/secret.txt
deny(file-write-create) $HOME/.aws/credentials
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unique denied path(s)"* ]]
  [[ "$output" == *"$HOME/Documents"* ]]
  [[ "$output" == *"$HOME/.aws"* ]]
}

@test "audit parses generic Permission denied patterns" {
  local log_file="$TEST_PROJECT/audit-generic.log"
  cat > "$log_file" <<EOF
$HOME/.gnupg/pubring.kbx: Permission denied
$HOME/Desktop/file.txt: Operation not permitted
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unique denied path(s)"* ]]
  [[ "$output" == *"$HOME/.gnupg"* ]]
  [[ "$output" == *"$HOME/Desktop"* ]]
}

@test "audit parses tool-prefixed denials and resolves relative paths via log cwd" {
  local log_file="$TEST_PROJECT/audit-prefixed.log"
  cat > "$log_file" <<EOF
# scode session: 2026-02-16T10:00:00-0800
# cwd: $TEST_PROJECT
#---
cat: /tmp/scode-prefixed-secret.txt: Permission denied
cat: ./relative-secret.txt: Permission denied
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unique denied path(s)"* ]]
  [[ "$output" == *"/tmp/scode-prefixed-secret.txt"* ]]
  [[ "$output" == *"$TEST_PROJECT/relative-secret.txt"* ]]
}

@test "audit parses Permission denied path containing colon" {
  local log_file="$TEST_PROJECT/audit-colon-perm.log"
  cat > "$log_file" <<'EOF'
cat: /tmp/my:file.txt: Permission denied
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 unique denied path(s)"* ]]
  [[ "$output" == *"/tmp/my:file.txt"* ]]
}

@test "audit parses Operation not permitted path containing colon" {
  local log_file="$TEST_PROJECT/audit-colon-op.log"
  cat > "$log_file" <<'EOF'
tool: /opt/data:cache/db.sqlite: Operation not permitted
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 unique denied path(s)"* ]]
  [[ "$output" == *"/opt/data:cache/db.sqlite"* ]]
}

@test "audit strips trailing slash from allowed metadata" {
  local log_file="$TEST_PROJECT/audit-trailing-slash.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-15T10:00:00-0800
# blocked: platform /tmp/scode-slash-parent
# allowed: /tmp/scode-slash-parent/child/
#---
deny(file-read-data) /tmp/scode-slash-parent/child/denied.txt
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  # The denied path is under the allowed subtree (after trailing-slash strip),
  # so it should NOT suggest the blocked parent as --allow.
  local parent_suggestion_count
  parent_suggestion_count="$(echo "$output" | grep -c '^  --allow /tmp/scode-slash-parent$' || true)"
  [ "$parent_suggestion_count" -eq 0 ]
}

@test "audit parses Node.js EACCES patterns" {
  local log_file="$TEST_PROJECT/audit-node.log"
  cat > "$log_file" <<EOF
Error: EACCES: permission denied, open '$HOME/.npmrc'
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 unique denied path(s)"* ]]
  [[ "$output" == *"$HOME/.npmrc"* ]]
}

@test "audit parses Python OSError patterns" {
  local log_file="$TEST_PROJECT/audit-python.log"
  cat > "$log_file" <<EOF
PermissionError: [Errno 13] Permission denied: '$HOME/.config/gcloud/credentials.db'
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 unique denied path(s)"* ]]
  [[ "$output" == *"$HOME/.config/gcloud"* ]]
}

@test "audit suggests correct --allow flags" {
  local log_file="$TEST_PROJECT/audit-suggest.log"
  cat > "$log_file" <<EOF
deny(file-read-data) $HOME/Documents/a.txt
deny(file-read-data) $HOME/Documents/b.txt
deny(file-write-create) $HOME/.aws/config
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--allow $HOME/Documents"* ]]
  [[ "$output" == *"--allow $HOME/.aws"* ]]
}

@test "audit deduplicates paths" {
  local log_file="$TEST_PROJECT/audit-dedup.log"
  cat > "$log_file" <<EOF
deny(file-read-data) $HOME/Documents/secret.txt
deny(file-read-metadata) $HOME/Documents/secret.txt
$HOME/Documents/secret.txt: Permission denied
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 unique denied path(s)"* ]]
}

@test "audit deduplicates --allow suggestions for interleaved parents" {
  local log_file="$TEST_PROJECT/audit-interleaved.log"
  cat > "$log_file" <<EOF
deny(file-read-data) $HOME/Documents/a.txt
deny(file-read-data) $HOME/.aws/creds
deny(file-read-data) $HOME/Documents/b.txt
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  # Count occurrences of --allow $HOME/Documents — should appear exactly once
  local count
  count=$(echo "$output" | grep -c "\\--allow $HOME/Documents" || true)
  [ "$count" -eq 1 ]
}

@test "audit shows caveat for uncategorized paths" {
  local log_file="$TEST_PROJECT/audit-caveat.log"
  cat > "$log_file" <<EOF
deny(file-read-data) /opt/custom/secret
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"audit only considers scode built-in defaults"* ]]
}

@test "audit with missing file errors" {
  run "$SCODE" audit /nonexistent/file.log
  [ "$status" -eq 1 ]
  [[ "$output" == *"log file not found"* ]]
}

@test "audit with empty file errors" {
  local log_file="$TEST_PROJECT/audit-empty.log"
  touch "$log_file"
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"log file is empty"* ]]
}

@test "audit without arguments errors" {
  run "$SCODE" audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "audit with extra arguments errors" {
  local log_file="$TEST_PROJECT/audit-one.log"
  echo "/tmp/audit-one: Permission denied" > "$log_file"
  run "$SCODE" audit "$log_file" extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "audit with no denial patterns in file" {
  local log_file="$TEST_PROJECT/audit-clean.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-14T10:00:00-0800
# command: claude
# no errors here, just comments
INFO: all clear
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no denial patterns found"* ]]
}

@test "audit categorizes platform-specific denials" {
  # Use a Linux-only default path and force Linux platform detection.
  local log_file="$TEST_PROJECT/audit-platform.log"
  cat > "$log_file" <<EOF
$HOME/.mozilla/firefox/profiles.ini: Permission denied
EOF
  _SCODE_PLATFORM=linux run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"platform"* ]]
  [[ "$output" == *"$HOME/.mozilla"* ]]
  [[ "$output" == *"--allow $HOME/.mozilla"* ]]
}

@test "audit reports uncategorized paths" {
  local log_file="$TEST_PROJECT/audit-uncat.log"
  cat > "$log_file" <<EOF
/opt/custom/secrets/key.pem: Permission denied
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not covered by scode defaults"* ]]
  [[ "$output" == *"/opt/custom/secrets/key.pem"* ]]
}

# ---------- audit policy-aware ----------

@test "log header includes blocked metadata with --block" {
  require_runtime_sandbox
  local log_file="$TEST_PROJECT/blocked-meta.log"
  run "$SCODE" --log "$log_file" --block /custom/secrets -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # The log must contain the CLI-blocked path with its source
  run grep '^# blocked: cli /custom/secrets$' "$log_file"
  [ "$status" -eq 0 ]
  # Should also contain default-blocked paths
  run grep '^# blocked: default ' "$log_file"
  [ "$status" -eq 0 ]
}

@test "linux runtime: --log records config and project blocked metadata entries" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local fake_bwrap="$fake_bin/bwrap"
  local config_file="$TEST_PROJECT/metadata-config.yaml"
  local log_file="$TEST_PROJECT/metadata-sources.log"
  local config_block="/tmp/scode-config-block-$$"
  local project_block="/tmp/scode-project-block-$$"

  mkdir -p "$fake_bin"
  cat > "$fake_bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    exec "$@"
  fi
  shift
done
echo "missing -- separator" >&2
exit 2
EOF
  chmod +x "$fake_bwrap"

  printf 'blocked:\n  - %s\n' "$config_block" > "$config_file"
  printf 'blocked:\n  - %s\n' "$project_block" > "$TEST_PROJECT/.scode.yaml"

  PATH="$fake_bin:$PATH" _SCODE_PLATFORM=linux run "$SCODE" --log "$log_file" --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  run grep "^# blocked: config ${config_block}$" "$log_file"
  [ "$status" -eq 0 ]
  run grep "^# blocked: project ${project_block}$" "$log_file"
  [ "$status" -eq 0 ]
}

@test "strict harness log includes read-only auto-allowed metadata on macOS" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  require_runtime_sandbox
  local fake_bin="$TEST_PROJECT/fake-bin"
  local fake_claude="$fake_bin/claude"
  local log_file="$TEST_PROJECT/strict-harness.log"

  mkdir -p "$fake_bin"
  cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_claude"

  PATH="$fake_bin:$PATH" run "$SCODE" --strict --log "$log_file" -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  run grep "^# allowed: ${HOME}/Library/Keychains$" "$log_file"
  [ "$status" -eq 0 ]
}

@test "audit recognizes custom-blocked paths from log metadata" {
  local log_file="$TEST_PROJECT/audit-custom.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-15T10:00:00-0800
# command: claude
# cwd: /tmp/test
# blocked: default /home/user/.aws
# blocked: cli /custom/secrets
#---
deny(file-read-data) /custom/secrets/key.pem
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Blocked by custom policy"* ]]
  [[ "$output" == *"/custom/secrets"* ]]
  # Must NOT suggest --allow for custom-blocked paths
  [[ "$output" != *"--allow /custom/secrets"* ]]
}

@test "audit falls back to defaults for old log format" {
  local log_file="$TEST_PROJECT/audit-old.log"
  cat > "$log_file" <<EOF
# scode session: 2026-02-14T10:00:00-0800
# command: claude
#---
$HOME/.aws/credentials: Permission denied
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  # Without # blocked: lines, falls back to built-in defaults
  [[ "$output" == *"Blocked by scode defaults"* ]]
  [[ "$output" == *"--allow $HOME/.aws"* ]]
}

@test "audit handles mix of default and custom blocked paths" {
  local log_file="$TEST_PROJECT/audit-mix.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-15T10:00:00-0800
# command: claude
# cwd: /tmp/test
# blocked: default /home/user/.aws
# blocked: platform /home/user/Library
# blocked: config /opt/internal/secrets
# blocked: cli /tmp/staging
#---
deny(file-read-data) /home/user/.aws/credentials
deny(file-read-data) /opt/internal/secrets/db.key
deny(file-read-data) /tmp/staging/data.csv
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  # Default paths shown under defaults
  [[ "$output" == *"Blocked by scode defaults"* ]]
  [[ "$output" == *"/home/user/.aws"* ]]
  [[ "$output" == *"--allow /home/user/.aws"* ]]
  # Custom paths shown under custom policy
  [[ "$output" == *"Blocked by custom policy"* ]]
  [[ "$output" == *"/opt/internal/secrets"* ]]
  [[ "$output" == *"/tmp/staging"* ]]
  # No --allow for custom-blocked paths
  [[ "$output" != *"--allow /opt/internal/secrets"* ]]
  [[ "$output" != *"--allow /tmp/staging"* ]]
}

@test "audit prefers custom block over broader default ancestor" {
  local log_file="$TEST_PROJECT/audit-custom-precedence.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-15T10:00:00-0800
# blocked: default /home/user/Documents
# blocked: cli /home/user/Documents/private
#---
deny(file-read-data) /home/user/Documents/private/token.txt
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Blocked by custom policy"* ]]
  [[ "$output" == *"/home/user/Documents/private"* ]]
  [[ "$output" != *"--allow /home/user/Documents"* ]]
  [[ "$output" != *"Blocked by scode defaults:"* ]]
}

@test "audit does not suggest blocked-parent allow when denied path is in logged allowed subtree" {
  local log_file="$TEST_PROJECT/audit-allowed-subtree.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-15T10:00:00-0800
# blocked: platform /tmp/scode-parent
# allowed: /tmp/scode-parent/allowed-subtree
#---
deny(file-read-data) /tmp/scode-parent/allowed-subtree/denied.txt
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  local parent_suggestion_count
  parent_suggestion_count="$(echo "$output" | grep -c '^  --allow /tmp/scode-parent$' || true)"
  [ "$parent_suggestion_count" -eq 0 ]
  [[ "$output" == *"Not covered by scode defaults"* ]]
  [[ "$output" == *"not in the logged blocked list"* ]]
}

@test "audit with metadata shows metadata-specific caveat for uncategorized" {
  local log_file="$TEST_PROJECT/audit-meta-uncat.log"
  cat > "$log_file" <<'EOF'
# scode session: 2026-02-15T10:00:00-0800
# blocked: default /home/user/.aws
#---
deny(file-read-data) /opt/unknown/thing
EOF
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in the logged blocked list"* ]]
  [[ "$output" != *"audit only considers scode built-in defaults"* ]]
}

# ---------- audit --watch ----------

@test "audit --watch with missing file fails" {
  run "$SCODE" audit --watch /nonexistent/path/to/log
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "audit -w is alias for --watch" {
  run "$SCODE" audit -w /nonexistent/path/to/log
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "audit --watch without logfile argument fails" {
  run "$SCODE" audit --watch
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

# ---------- audit --watch happy-path ----------

@test "audit --watch prints denials from appended lines" {
  local log_file="$TEST_PROJECT/watch-test.log"
  local out_file="$TEST_PROJECT/watch-out.txt"
  local watch_pid=""
  touch "$log_file"

  # Start audit --watch in background, capture output
  "$SCODE" audit --watch "$log_file" > "$out_file" 2>&1 &
  watch_pid=$!

  # Poll until tail -f is running (output file has the "watching" header)
  local attempts=0
  while ! grep -q "watching" "$out_file" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -ge 20 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for audit --watch to start"
    fi
    sleep 0.1
  done

  # Append denial lines
  echo "deny(file-read-data) /tmp/watch-test-path-1" >> "$log_file"
  echo "deny(file-write-data) /tmp/watch-test-path-2" >> "$log_file"
  # Append a duplicate (should be deduped)
  echo "deny(file-read-data) /tmp/watch-test-path-1" >> "$log_file"

  # Poll until both unique denials appear in output.
  # Pattern anchored to "[N] DENIED:" to avoid matching bash job-control output.
  attempts=0
  while true; do
    local count
    count=$(grep -cE '^\[.*\] DENIED:' "$out_file" 2>/dev/null || true)
    [[ "$count" -ge 2 ]] && break
    attempts=$((attempts + 1))
    if [[ $attempts -ge 40 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for denial output (got $count, want 2)"
    fi
    sleep 0.1
  done

  stop_watch_process "$watch_pid"
  watch_pid=""

  # Verify content
  local watch_output
  watch_output="$(cat "$out_file")"
  [[ "$watch_output" == *"/tmp/watch-test-path-1"* ]]
  [[ "$watch_output" == *"/tmp/watch-test-path-2"* ]]

  # Exactly 2 denials (dedup removes the third line)
  local final_count
  final_count=$(grep -cE '^\[.*\] DENIED:' "$out_file" || true)
  [ "$final_count" -eq 2 ]
}

@test "audit -w prints denials from appended lines" {
  local log_file="$TEST_PROJECT/watch-short.log"
  local out_file="$TEST_PROJECT/watch-short-out.txt"
  local watch_pid=""
  touch "$log_file"

  "$SCODE" audit -w "$log_file" > "$out_file" 2>&1 &
  watch_pid=$!

  local attempts=0
  while ! grep -q "watching" "$out_file" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -ge 20 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for audit -w to start"
    fi
    sleep 0.1
  done

  echo "deny(file-read-data) /tmp/watch-short-path" >> "$log_file"

  attempts=0
  while true; do
    local count
    count=$(grep -cE '^\[.*\] DENIED:' "$out_file" 2>/dev/null || true)
    [[ "$count" -ge 1 ]] && break
    attempts=$((attempts + 1))
    if [[ $attempts -ge 40 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for audit -w denial output"
    fi
    sleep 0.1
  done

  stop_watch_process "$watch_pid"
  watch_pid=""

  local watch_output
  watch_output="$(cat "$out_file")"
  [[ "$watch_output" == *"/tmp/watch-short-path"* ]]
}

@test "audit --watch ignores pre-existing denials and follows new lines only" {
  local log_file="$TEST_PROJECT/watch-existing.log"
  local out_file="$TEST_PROJECT/watch-existing-out.txt"
  local watch_pid=""
  touch "$log_file"
  echo "deny(file-read-data) /tmp/watch-existing-old" >> "$log_file"

  "$SCODE" audit --watch "$log_file" > "$out_file" 2>&1 &
  watch_pid=$!

  local attempts=0
  while ! grep -q "watching" "$out_file" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -ge 20 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for audit --watch to start"
    fi
    sleep 0.1
  done

  echo "deny(file-read-data) /tmp/watch-existing-new" >> "$log_file"

  attempts=0
  while true; do
    local count
    count=$(grep -cE '^\[.*\] DENIED:' "$out_file" 2>/dev/null || true)
    [[ "$count" -ge 1 ]] && break
    attempts=$((attempts + 1))
    if [[ $attempts -ge 40 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for denial output"
    fi
    sleep 0.1
  done

  stop_watch_process "$watch_pid"
  watch_pid=""

  local watch_output
  watch_output="$(cat "$out_file")"
  [[ "$watch_output" != *"/tmp/watch-existing-old"* ]]
  [[ "$watch_output" == *"/tmp/watch-existing-new"* ]]

  local final_count
  final_count=$(grep -cE '^\[.*\] DENIED:' "$out_file" || true)
  [ "$final_count" -eq 1 ]
}

# ---------- audit_watch log_cwd regression ----------

@test "audit --watch resolves relative paths via log cwd" {
  local log_file="$TEST_PROJECT/watch-cwd.log"
  local out_file="$TEST_PROJECT/watch-cwd-out.txt"
  local watch_pid=""
  # Create a log with cwd metadata
  cat > "$log_file" <<'EOF'
# scode session: test
# cwd: /home/testuser/project
#---
EOF

  # Start audit --watch in background
  "$SCODE" audit --watch "$log_file" > "$out_file" 2>&1 &
  watch_pid=$!

  # Poll until watch is running
  local attempts=0
  while ! grep -q "watching" "$out_file" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -ge 20 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for audit --watch to start"
    fi
    sleep 0.1
  done

  # Append a denial with a relative path
  echo "deny(file-read-data) ./src/secret.txt" >> "$log_file"

  # Poll until the denial appears
  attempts=0
  while true; do
    local count
    count=$(grep -cE '^\[.*\] DENIED:' "$out_file" 2>/dev/null || true)
    [[ "$count" -ge 1 ]] && break
    attempts=$((attempts + 1))
    if [[ $attempts -ge 40 ]]; then
      stop_watch_process "$watch_pid"
      fail "timed out waiting for denial output"
    fi
    sleep 0.1
  done

  stop_watch_process "$watch_pid"
  watch_pid=""

  local watch_output
  watch_output="$(cat "$out_file")"
  # Relative path should be resolved using the logged cwd
  [[ "$watch_output" == *"/home/testuser/project/src/secret.txt"* ]]
}

# ---------- Packaging: make install/uninstall dry-run ----------

@test "Makefile has install and uninstall targets" {
  local makefile="$BATS_TEST_DIRNAME/../Makefile"
  [[ -f "$makefile" ]]
  grep -q "^install:" "$makefile"
  grep -q "^uninstall:" "$makefile"
}

@test "Makefile has test and lint targets" {
  local makefile="$BATS_TEST_DIRNAME/../Makefile"
  [[ -f "$makefile" ]]
  grep -q "^test:" "$makefile"
  grep -q "^lint:" "$makefile"
}
