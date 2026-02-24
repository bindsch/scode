#!/usr/bin/env bats
# Linux bubblewrap sandbox generation

load test_helper

LOCAL_TCP_SERVER_PID=""

start_local_tcp_server() {
  local port_file="$1"
  local ready_file="$2"
  node - "$port_file" "$ready_file" <<'NODE' &
const fs = require('fs');
const net = require('net');

const [portFile, readyFile] = process.argv.slice(2);
const server = net.createServer(socket => {
  socket.end('ok');
});

server.on('error', err => {
  fs.writeFileSync(readyFile, `error:${err.message}`);
  process.exit(1);
});

server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(portFile, String(server.address().port));
  fs.writeFileSync(readyFile, 'ready');
});

setTimeout(() => {
  server.close(() => process.exit(0));
}, 15000);
NODE
  LOCAL_TCP_SERVER_PID=$!
}

wait_for_file() {
  local file_path="$1"
  local attempts="$2"
  local i
  for ((i=0; i<attempts; i++)); do
    [[ -f "$file_path" ]] && return 0
    sleep 0.1
  done
  return 1
}

# ---------- Linux dry-run tests (via _SCODE_PLATFORM override) ----------

@test "linux dry-run: generates bwrap command" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"bwrap"* ]]
  [[ "$output" == *"# Platform: Linux (bubblewrap)"* ]]
}

@test "linux dry-run: binds HOME" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind $HOME $HOME"* ]]
}

@test "linux dry-run: blocks default dirs with --tmpfs" {
  # Non-existent dirs are now pre-blocked (no need for dirs to exist on host)
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tmpfs $HOME/Documents"* ]]
  [[ "$output" == *"--tmpfs $HOME/Desktop"* ]]
  [[ "$output" == *"--tmpfs $HOME/Pictures"* ]]
}

@test "linux dry-run: includes Linux-specific blocks" {
  # Non-existent dirs are pre-blocked if parent exists.
  # Check every LINUX_EXTRA_BLOCKED entry whose parent exists on this host.
  run linux_dry_run true
  [ "$status" -eq 0 ]

  # Personal files (parent: $HOME — always exists)
  [[ "$output" == *"$HOME/Videos"* ]]

  # Cloud credentials (parent: $HOME/.config or $HOME)
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/doctl"* ]]
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/helm"* ]]
  [[ "$output" == *"$HOME/.terraform.d"* ]]

  # Password managers / keyrings
  # "Bitwarden CLI" has a space — printf %q escapes it to "Bitwarden\ CLI"
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/Bitwarden\\ CLI"* ]]
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/Bitwarden"* ]]
  [[ ! -d "$HOME/.local/share" ]] || [[ "$output" == *"$HOME/.local/share/keyrings"* ]]
  [[ ! -d "$HOME/.local/share" ]] || [[ "$output" == *"$HOME/.local/share/kwalletd"* ]]

  # Auth tokens
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/pip"* ]]
  [[ ! -d "$HOME/.config/git" ]] || [[ "$output" == *"$HOME/.config/git/credentials"* ]]

  # Browser profiles
  [[ "$output" == *"$HOME/.mozilla"* ]]
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/google-chrome"* ]]
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/chromium"* ]]
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/BraveSoftware"* ]]

  # Email / messaging
  [[ "$output" == *"$HOME/.thunderbird"* ]]
  [[ ! -d "$HOME/.config" ]] || [[ "$output" == *"$HOME/.config/Signal"* ]]

  # Flatpak / Snap
  [[ ! -d "$HOME/.var" ]] || [[ "$output" == *"$HOME/.var/app"* ]]
  [[ "$output" == *"$HOME/snap"* ]]
}

@test "linux dry-run: --block adds custom dir" {
  mkdir -p "$TEST_PROJECT/linux-secret"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --block "$TEST_PROJECT/linux-secret" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tmpfs ${real_project}/linux-secret"* ]]
}

@test "linux dry-run: --allow child path re-binds under blocked parent" {
  # Use --block/--allow pair with absolute paths to avoid HOME/realpath mismatch
  mkdir -p "$TEST_PROJECT/secret/subdir"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run \
    --block "$TEST_PROJECT/secret" \
    --allow "$TEST_PROJECT/secret/subdir" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # Parent should be blocked (tmpfs)
  [[ "$output" == *"--tmpfs ${real_project}/secret"* ]]
  # Child should be re-bound
  [[ "$output" == *"--bind ${real_project}/secret/subdir ${real_project}/secret/subdir"* ]]
}

@test "linux dry-run: warns when --allow child under blocked parent is missing" {
  local blocked_parent="$TEST_PROJECT/secret-missing"
  local missing_child="$blocked_parent/subdir"
  mkdir -p "$blocked_parent"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run \
    --block "$blocked_parent" \
    --allow "$missing_child" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"linux default mode: allowed path does not exist"* ]]
  [[ "$output" == *"${missing_child}"* ]]
}

@test "linux dry-run: --strict uses minimal binds (no HOME)" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Mode: strict"* ]]
  # Strict should NOT bind HOME
  [[ "$output" != *"--bind $HOME $HOME"* ]]
  # But should have system dirs
  [[ "$output" == *"--ro-bind /usr /usr"* ]]
}

@test "linux dry-run: --strict --block outside bound mounts is ignored" {
  local outside_block="$HOME/.scode-strict-outside-bound-$$"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict \
    --block "$outside_block" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"--tmpfs ${outside_block}"* ]]
  [[ "$output" != *"--ro-bind /dev/null ${outside_block}"* ]]
  [[ "$output" != *"${outside_block}"* ]]
}

@test "linux dry-run: --no-net adds --unshare-net" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --no-net -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--unshare-net"* ]]
}

@test "linux dry-run: --ro binds project read-only" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --ro -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # realpath may resolve /var -> /private/var on macOS
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  [[ "$output" == *"--ro-bind ${real_project}"* ]]
}

@test "linux runtime: executes through bwrap invocation path" {
  local fake_bin="$TEST_PROJECT/fake-bin"
  local fake_bwrap="$fake_bin/bwrap"
  local bwrap_log="$TEST_PROJECT/bwrap-args.log"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"

  mkdir -p "$fake_bin"
  cat > "$fake_bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${BWRAP_LOG_FILE:?missing BWRAP_LOG_FILE}"
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

  PATH="$fake_bin:$PATH" BWRAP_LOG_FILE="$bwrap_log" run linux_runtime true
  [ "$status" -eq 0 ]
  [ -f "$bwrap_log" ]

  local args
  args="$(cat "$bwrap_log")"
  [[ "$args" == *"--bind $HOME $HOME"* ]]
  [[ "$args" == *"--chdir ${real_project}"* ]]
}

@test "linux runtime: real bwrap command runs on linux hosts" {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

@test "linux runtime: default network allows localhost TCP connect" {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  command -v node >/dev/null 2>&1 || skip "node not installed"
  local port_file="$TEST_PROJECT/linux-net-port-default"
  local ready_file="$TEST_PROJECT/linux-net-ready-default"
  start_local_tcp_server "$port_file" "$ready_file"
  local server_pid="$LOCAL_TCP_SERVER_PID"

  wait_for_file "$ready_file" 60 || fail "timed out waiting for local TCP server"
  [[ "$(cat "$ready_file")" == "ready" ]]
  local port
  port="$(cat "$port_file")"

  run "$SCODE" -C "$TEST_PROJECT" -- node -e "
    const net = require('net');
    const socket = net.connect({ host: '127.0.0.1', port: ${port} }, () => {
      console.log('CONNECTED');
      socket.end();
    });
    socket.on('error', err => {
      console.error(err.code || err.message);
      process.exit(21);
    });
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONNECTED"* ]]
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}

@test "linux runtime: --no-net blocks localhost TCP connect" {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  command -v node >/dev/null 2>&1 || skip "node not installed"
  local port_file="$TEST_PROJECT/linux-net-port-nonet"
  local ready_file="$TEST_PROJECT/linux-net-ready-nonet"
  start_local_tcp_server "$port_file" "$ready_file"
  local server_pid="$LOCAL_TCP_SERVER_PID"

  wait_for_file "$ready_file" 60 || fail "timed out waiting for local TCP server"
  [[ "$(cat "$ready_file")" == "ready" ]]
  local port
  port="$(cat "$port_file")"

  run "$SCODE" --no-net -C "$TEST_PROJECT" -- node -e "
    const net = require('net');
    const socket = net.connect({ host: '127.0.0.1', port: ${port} }, () => {
      console.log('CONNECTED');
      socket.end();
    });
    socket.on('error', err => {
      console.error(err.code || err.message);
      process.exit(22);
    });
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"CONNECTED"* ]]
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}

@test "linux runtime: --block denies reads to blocked path" {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  local blocked_dir="$TEST_PROJECT/linux-runtime-blocked"
  mkdir -p "$blocked_dir"
  echo "linux-secret" > "$blocked_dir/secret.txt"

  run "$SCODE" --block "$blocked_dir" -C "$TEST_PROJECT" -- cat "$blocked_dir/secret.txt"
  [ "$status" -ne 0 ]
}

@test "linux runtime: --allow child path overrides parent --block" {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  local blocked_parent="$TEST_PROJECT/linux-runtime-parent"
  local allowed_child="$blocked_parent/allowed-child"
  mkdir -p "$allowed_child"
  echo "linux-allowed" > "$allowed_child/value.txt"

  run "$SCODE" --block "$blocked_parent" --allow "$allowed_child" -C "$TEST_PROJECT" -- cat "$allowed_child/value.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linux-allowed"* ]]
}

# ---------- Linux: file vs dir blocking ----------

@test "linux dry-run: file path uses ro-bind /dev/null instead of tmpfs" {
  # Create a file (not dir) to block
  touch "$TEST_PROJECT/secret-token"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run \
    --block "$TEST_PROJECT/secret-token" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /dev/null ${real_project}/secret-token"* ]]
  [[ "$output" != *"--tmpfs ${real_project}/secret-token"* ]]
}

@test "linux dry-run: nonexistent blocked path is skipped" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run \
    --block /nonexistent/path/xyz \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"/nonexistent/path/xyz"* ]]
}

# ---------- Linux: bwrap security flags ----------

@test "linux dry-run: includes --unshare-pid" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--unshare-pid"* ]]
}

@test "linux dry-run: includes --unshare-ipc" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--unshare-ipc"* ]]
}

@test "linux dry-run: includes --die-with-parent" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--die-with-parent"* ]]
}

# ---------- Linux: privilege escalation ----------

@test "linux dry-run: blocks sudo/su/login" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/bin/sudo"* ]] || [[ "$output" == *"--ro-bind /dev/null /usr/bin/sudo"* ]]
}

# ---------- Linux: XDG_RUNTIME_DIR ----------

@test "linux dry-run: binds XDG_RUNTIME_DIR when set" {
  XDG_RUNTIME_DIR="/run/user/1000" _SCODE_PLATFORM=linux run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind /run/user/1000 /run/user/1000"* ]]
}

# ---------- Linux: --strict does not bind HOME ----------

@test "linux dry-run: --strict omits XDG_RUNTIME_DIR" {
  XDG_RUNTIME_DIR="/run/user/1000" _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"--bind /run/user/1000"* ]]
}

# ---------- Linux: non-existent path blocking ----------

@test "linux dry-run: non-existent dir under HOME is still blocked" {
  # Ensure the path does NOT exist
  [[ -e "$HOME/.scode-test-nonexistent-$$" ]] && skip "test dir unexpectedly exists"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run \
    --block "$HOME/.scode-test-nonexistent-$$" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tmpfs $HOME/.scode-test-nonexistent-$$"* ]]
}

@test "linux dry-run: non-existent path with missing parent is skipped" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run \
    --block /nonexistent-parent-$$/child \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"/nonexistent-parent-$$"* ]]
}

# ---------- Linux strict: file-level --allow ----------

@test "linux dry-run: --strict --allow works for files" {
  local test_file="$TEST_PROJECT/allowed-file.txt"
  touch "$test_file"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict \
    --allow "$test_file" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind ${real_project}/allowed-file.txt ${real_project}/allowed-file.txt"* ]]
}

@test "linux dry-run: --strict warns and skips missing --allow path" {
  local missing_allow="$TEST_PROJECT/missing-allow-dir"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict \
    --allow "$missing_allow" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict mode: allowed path does not exist"* ]]
  [[ "$output" == *"${missing_allow}"* ]]
  [[ "$output" != *"--bind ${missing_allow} ${missing_allow}"* ]]
}

# ---------- New default blocks: cross-platform ----------

@test "linux dry-run: blocks cross-platform credential files" {
  run linux_dry_run true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.pypirc"* ]]
  [[ "$output" == *"$HOME/.config/gh"* ]]
  [[ "$output" == *"$HOME/.config/hub"* ]]
}

# ---------- Linux: project dir under blocked parent ----------

@test "linux dry-run: project dir under blocked parent is re-bound" {
  local blocked_parent="$TEST_PROJECT/linux-blocked"
  local project="$blocked_parent/myproject"
  mkdir -p "$project"
  local real_project
  real_project="$(realpath "$project")"
  local real_blocked
  real_blocked="$(realpath "$blocked_parent")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --block "$blocked_parent" -C "$project" -- true
  [ "$status" -eq 0 ]
  # Parent should be blocked
  [[ "$output" == *"--tmpfs ${real_blocked}"* ]]
  # Project should be re-bound after
  [[ "$output" == *"--bind ${real_project} ${real_project}"* ]]
}

# ---------- Linux dry-run: config scalars ----------

@test "linux dry-run: config net: off adds --unshare-net" {
  local config_file="$TEST_PROJECT/linux-net.yaml"
  cat > "$config_file" <<'YAML'
net: off
YAML
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--unshare-net"* ]]
}

@test "linux dry-run: config fs_mode: ro binds project read-only" {
  local config_file="$TEST_PROJECT/linux-fs.yaml"
  cat > "$config_file" <<'YAML'
fs_mode: ro
YAML
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind ${real_project}"* ]]
}

@test "linux dry-run: config strict: true uses strict mode" {
  local config_file="$TEST_PROJECT/linux-strict.yaml"
  cat > "$config_file" <<'YAML'
strict: true
YAML
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Mode: strict"* ]]
  [[ "$output" != *"--bind $HOME $HOME"* ]]
}

@test "linux dry-run: --scrub-env scrubs vars" {
  export OPENAI_API_KEY="linux-test-key"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scrubbed env vars"* ]]
  [[ "$output" == *"OPENAI_API_KEY"* ]]
  unset OPENAI_API_KEY
}

# ---------- Linux strict: allow overrides block ----------

@test "linux dry-run: --block on project subdir re-blocks after project bind" {
  local blocked_parent="/tmp/scode-fix10-linux-$$"
  local project_dir="$blocked_parent/myproject"
  local secret_dir="$project_dir/secrets"
  mkdir -p "$secret_dir"
  local real_secret_dir
  real_secret_dir="$(realpath "$secret_dir")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --block "$blocked_parent" --block "$secret_dir" -C "$project_dir" -- true
  [ "$status" -eq 0 ]
  # The bwrap args should contain --tmpfs for the secrets subdir after the project bind
  [[ "$output" == *"--tmpfs ${real_secret_dir}"* ]]
  rm -rf "$blocked_parent"
}

@test "linux dry-run: --strict allow overrides --block under allowed parent" {
  mkdir -p "$TEST_PROJECT/secrets/tokens"
  local real_project
  real_project="$(realpath "$TEST_PROJECT")"
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --strict \
    --allow "$TEST_PROJECT/secrets" \
    --block "$TEST_PROJECT/secrets/tokens" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind ${real_project}/secrets ${real_project}/secrets"* ]]
  [[ "$output" != *"--tmpfs ${real_project}/secrets/tokens"* ]]
}
