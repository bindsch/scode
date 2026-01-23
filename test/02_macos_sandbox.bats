#!/usr/bin/env bats
# macOS sandbox-exec profile generation

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

# ---------- Dry-run profile generation (macOS) ----------

@test "dry-run generates sandbox profile" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(version 1)"* ]]
  [[ "$output" == *"(allow default)"* ]]
  [[ "$output" == *"# Command: true"* ]]
}

@test "dry-run: default blocks personal directories" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/Documents"* ]]
  [[ "$output" == *"$HOME/Desktop"* ]]
  [[ "$output" == *"$HOME/.aws"* ]]
  [[ "$output" == *"$HOME/.gnupg"* ]]
}

@test "dry-run: default blocks auth tokens" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.npmrc"* ]]
  [[ "$output" == *"$HOME/.netrc"* ]]
  [[ "$output" == *"$HOME/.git-credentials"* ]]
  [[ "$output" == *"$HOME/.password-store"* ]]
  [[ "$output" == *"$HOME/.pypirc"* ]]
  [[ "$output" == *"$HOME/.cargo/credentials.toml"* ]]
  [[ "$output" == *"$HOME/.config/gh"* ]]
  [[ "$output" == *"$HOME/.config/hub"* ]]
}

@test "dry-run: ~/.ssh is NOT blocked by default" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  # SSH should be accessible for git operations
  local blocked_section
  blocked_section=$(echo "$output" | sed -n '/Blocked directories/,/^$/p')
  [[ "$blocked_section" != *"$HOME/.ssh"* ]]
}

@test "dry-run: macOS blocks ~/Library" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(subpath \"$HOME/Library\")"* ]]
}

@test "dry-run: macOS carves out read-write ~/Library subdirs" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"carve-outs (read-write)"* ]]
  [[ "$output" == *"$HOME/Library/Application Support"* ]]
  [[ "$output" == *"$HOME/Library/Caches"* ]]
  [[ "$output" == *"$HOME/Library/Preferences"* ]]
}

@test "dry-run: macOS carves out read-only ~/Library/Keychains" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"carve-outs (read-only)"* ]]
  [[ "$output" == *"$HOME/Library/Keychains"* ]]
  # Keychains should be file-read* only, NOT file-write*
  local keychains_section
  keychains_section=$(echo "$output" | sed -n '/read-only/,/^$/p')
  [[ "$keychains_section" == *"(allow file-read*"* ]]
  [[ "$keychains_section" != *"file-write*"* ]]
}

@test "dry-run: --allow suppresses a Library carve-out" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # If user explicitly --allows ~/Library, the deny is removed entirely
  # so carve-outs are not needed
  run "$SCODE" --dry-run --allow "$HOME/Library" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"(subpath \"$HOME/Library\")"* ]]
  [[ "$output" != *"carve-outs"* ]]
}

@test "dry-run: blocks privilege escalation" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/bin/sudo"* ]]
  [[ "$output" == *"/usr/bin/su"* ]]
}

@test "dry-run: --no-net denies network" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --no-net -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny network"* ]]
}

@test "dry-run: default allows network" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" != *"(deny network"* ]]
}

# ---------- Runtime behavior checks ----------

@test "macOS runtime: default network allows localhost TCP connect" {
  require_runtime_sandbox
  require_node
  local port_file="$TEST_PROJECT/net-port-default"
  local ready_file="$TEST_PROJECT/net-ready-default"
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
      process.exit(11);
    });
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONNECTED"* ]]
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}

@test "macOS runtime: --no-net blocks localhost TCP connect" {
  require_runtime_sandbox
  require_node
  local port_file="$TEST_PROJECT/net-port-nonet"
  local ready_file="$TEST_PROJECT/net-ready-nonet"
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
      process.exit(12);
    });
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"CONNECTED"* ]]
  echo "$output" | grep -Eq "EPERM|EACCES|Operation not permitted|Permission denied|deny\\(network"
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}

@test "macOS runtime: --block denies reads to blocked path" {
  require_runtime_sandbox
  local blocked_dir="$TEST_PROJECT/runtime-blocked"
  mkdir -p "$blocked_dir"
  echo "blocked-secret" > "$blocked_dir/secret.txt"

  run "$SCODE" --block "$blocked_dir" -C "$TEST_PROJECT" -- cat "$blocked_dir/secret.txt"
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq "Permission denied|Operation not permitted|deny\\(file-read"
}

@test "macOS runtime: --allow child path overrides parent --block" {
  require_runtime_sandbox
  local blocked_parent="$TEST_PROJECT/runtime-parent"
  local allowed_child="$blocked_parent/allowed-child"
  mkdir -p "$allowed_child"
  echo "allowed-value" > "$allowed_child/value.txt"

  run "$SCODE" --block "$blocked_parent" --allow "$allowed_child" -C "$TEST_PROJECT" -- cat "$allowed_child/value.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowed-value"* ]]
}

@test "dry-run: --ro makes project read-only" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --ro -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"read-only"* ]]
  [[ "$output" == *"(deny file-write*"* ]]
}

@test "dry-run: --block adds custom blocked dir" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --block /tmp/fake-secret -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/fake-secret"* ]]
}

@test "dry-run: --allow removes dir from blocked list" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # Documents is blocked by default; --allow should remove it
  run "$SCODE" --dry-run --allow "$HOME/Documents" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # Documents should NOT appear in the blocked directories section
  local blocked_section
  blocked_section=$(echo "$output" | sed -n '/Blocked directories/,/^$/p')
  [[ "$blocked_section" != *"$HOME/Documents"* ]]
}

@test "dry-run: --allow parent path unblocks blocked descendants" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # Firewall-style allow: permitting HOME should permit all descendants.
  run "$SCODE" --dry-run --allow "$HOME" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  local blocked_section
  blocked_section=$(echo "$output" | sed -n '/Blocked directories/,/^$/p')
  [[ "$blocked_section" != *"$HOME/Documents"* ]]
  [[ "$blocked_section" != *"$HOME/.aws"* ]]
  [[ "$blocked_section" != *"$HOME/Library"* ]]
}

@test "dry-run: --allow child path overrides parent block" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # ~/Documents is blocked by default, but --allow ~/Documents/projects
  # should emit an explicit allow rule for the child path
  run "$SCODE" --dry-run --allow "$HOME/Documents/projects" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # Parent is still blocked
  [[ "$output" == *"$HOME/Documents"* ]]
  # Child has an explicit allow override
  [[ "$output" == *"Explicitly allowed"* ]]
  [[ "$output" == *"$HOME/Documents/projects"* ]]
}

@test "dry-run: multiple --block flags accumulate" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --block /tmp/a --block /tmp/b -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/a"* ]]
  [[ "$output" == *"/tmp/b"* ]]
}

# ---------- Strict mode ----------

@test "dry-run: --strict uses deny-default" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny default)"* ]]
  [[ "$output" == *'(import "system.sb")'* ]]
  [[ "$output" == *"Mode: strict"* ]]
}

@test "dry-run: --strict allows system essentials" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *'(subpath "/usr")'* ]]
  [[ "$output" == *'(subpath "/System")'* ]]
  [[ "$output" == *'(subpath "/bin")'* ]]
}

@test "dry-run: --strict allows /opt for package-managed tools" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *'(subpath "/opt")'* ]]
}

@test "macOS runtime: --strict executes simple commands" {
  require_runtime_sandbox
  run "$SCODE" --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

@test "dry-run: --strict allows project dir" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_PROJECT"* ]]
}

@test "dry-run: --strict --ro makes project read-only" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict --ro -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"read-only"* ]]
  # Should have file-read but not file-write for project
  [[ "$output" == *"(allow file-read*"* ]]
}

@test "dry-run: --strict --no-net has no network-allow" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict --no-net -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"(allow network"* ]]
}

@test "dry-run: --strict allows scode lib dir for preload" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scode lib directory"* ]]
  [[ "$output" == *"Node.js preload"* ]]
}

# ---------- Path sanitization ----------

@test "rejects --block path with newline" {
  local bad_path
  bad_path=$'/tmp/evil\npath'
  run "$SCODE" --dry-run --block "$bad_path" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid path"* ]]
}

@test "dry-run: --block escapes quotes in path" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # A path with a double-quote should be escaped in the SBPL profile
  run "$SCODE" --dry-run --block '/tmp/has"quote' -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # The profile should contain the escaped form: has\"quote
  [[ "$output" == *'has\"quote'* ]]
}

# ---------- Strict mode + blocked entries ----------

@test "dry-run: --strict honors --block" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict --block /tmp/strict-block -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny default)"* ]]
  [[ "$output" == *"/tmp/strict-block"* ]]
  [[ "$output" == *"Blocked directories"* ]]
}

@test "dry-run: --strict with config blocked" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local config_file="$TEST_PROJECT/strict-blocked.yaml"
  cat > "$config_file" <<'YAML'
strict: true
blocked:
  - /tmp/cfg-strict-block
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny default)"* ]]
  [[ "$output" == *"/tmp/cfg-strict-block"* ]]
}

# ---------- macOS: --strict --allow ----------

@test "dry-run: --strict --allow emits allow rule for specified dir" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local allow_dir="$TEST_PROJECT/strict-allow-test"
  mkdir -p "$allow_dir"
  local real_dir
  real_dir="$(realpath "$allow_dir")"
  run "$SCODE" --dry-run --strict --allow "$allow_dir" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny default)"* ]]
  [[ "$output" == *"Explicitly allowed"* ]]
  [[ "$output" == *"${real_dir}"* ]]
}

@test "dry-run: --strict warns when --allow path is missing" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local missing_allow="$TEST_PROJECT/missing-allow-dir"
  run "$SCODE" --dry-run --strict --allow "$missing_allow" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict mode: allowed path does not exist"* ]]
  [[ "$output" == *"${missing_allow}"* ]]
}

@test "dry-run: --allow outside blocked parents emits no explicit allow section" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local allow_dir="$TEST_PROJECT/safe-allow"
  mkdir -p "$allow_dir"
  run "$SCODE" --dry-run --allow "$allow_dir" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"Explicitly allowed directories"* ]]
}

# ---------- macOS: project dir under blocked parent ----------

@test "dry-run: project dir under blocked parent gets explicit allow" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # Create a project inside a blocked parent
  local blocked_parent="$TEST_PROJECT/blocked-parent"
  local project="$blocked_parent/myproject"
  mkdir -p "$project"
  local real_project
  real_project="$(realpath "$project")"
  run "$SCODE" --dry-run --block "$blocked_parent" -C "$project" -- true
  [ "$status" -eq 0 ]
  # Parent should be blocked
  [[ "$output" == *"(deny file-read* file-write*"* ]]
  # Project should have an explicit allow override
  [[ "$output" == *"override blocked parent"* ]]
  [[ "$output" == *"(allow file-read* file-write*"* ]]
  [[ "$output" == *"${real_project}"* ]]
}

@test "dry-run: project dir under blocked parent with --ro is read-only" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_parent="$TEST_PROJECT/blocked-parent-ro"
  local project="$blocked_parent/myproject"
  mkdir -p "$project"
  local real_project
  real_project="$(realpath "$project")"
  run "$SCODE" --dry-run --ro --block "$blocked_parent" -C "$project" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"override blocked parent, read-only"* ]]
  # Should allow file-read but not file-write in the override
  local override_section
  override_section=$(echo "$output" | sed -n '/override blocked parent/,/)$/p')
  [[ "$override_section" == *"(allow file-read*"* ]]
  [[ "$override_section" != *"file-write*"* ]]
}

@test "dry-run: project dir NOT under blocked parent emits no override" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" != *"override blocked parent"* ]]
}

# ---------- SBPL escaping: backslash in path ----------

@test "dry-run: --block escapes backslash in path" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --block '/tmp/has\backslash' -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # The profile should contain the escaped form: has\\backslash
  [[ "$output" == *'has\\backslash'* ]]
}

# ---------- Dry-run: sandbox environment display ----------

@test "dry-run: shows sandbox environment variables" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sandbox environment:"* ]]
  [[ "$output" == *"SCODE_SANDBOXED=1"* ]]
  [[ "$output" == *"ELECTRON_DISABLE_SANDBOX=1"* ]]
  [[ "$output" == *"CHROMIUM_FLAGS="* ]]
}

# ---------- Privilege escalation: doas/pkexec ----------

@test "dry-run: blocks doas and pkexec" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/bin/doas"* ]]
  [[ "$output" == *"/usr/bin/pkexec"* ]]
}

# ---------- macOS runtime: --cwd ----------

@test "macOS runtime: -C sets working directory for command" {
  require_runtime_sandbox
  local alt_dir="$TEST_PROJECT/alt-cwd"
  mkdir -p "$alt_dir"
  local real_alt
  real_alt="$(realpath "$alt_dir")"
  local val
  val=$("$SCODE" -C "$alt_dir" -- pwd 2>/dev/null)
  [[ "$val" == "$real_alt" ]]
}

# ---------- P1 regression: strict mode allow/deny ordering ----------

@test "dry-run: --strict --allow child of blocked parent emits allow AFTER deny" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_dir="$TEST_PROJECT/blocked-parent"
  local allow_dir="$TEST_PROJECT/blocked-parent/child"
  mkdir -p "$allow_dir"
  run "$SCODE" --dry-run --strict --block "$blocked_dir" --allow "$allow_dir" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # The allow rule must appear AFTER the deny rule so it wins (later rules win)
  local deny_pos allow_pos
  deny_pos=$(echo "$output" | grep -n "Blocked directories" | head -1 | cut -d: -f1)
  allow_pos=$(echo "$output" | grep -n "Explicitly allowed" | head -1 | cut -d: -f1)
  [ -n "$deny_pos" ]
  [ -n "$allow_pos" ]
  [ "$deny_pos" -lt "$allow_pos" ]
}

@test "dry-run: --strict blocked dirs appear before harness auto-allow" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_dir="$TEST_PROJECT/blocked-strict-order"
  mkdir -p "$blocked_dir"
  run "$SCODE" --dry-run --strict --block "$blocked_dir" -C "$TEST_PROJECT" -- claude
  [ "$status" -eq 0 ]
  # Blocked must precede any harness auto-allowed section
  if [[ "$output" == *"Harness auto-allowed"* ]]; then
    local deny_pos harness_pos
    deny_pos=$(echo "$output" | grep -n "Blocked directories" | head -1 | cut -d: -f1)
    harness_pos=$(echo "$output" | grep -n "Harness auto-allowed" | head -1 | cut -d: -f1)
    [ "$deny_pos" -lt "$harness_pos" ]
  fi
}
