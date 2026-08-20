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

@test "dry-run: ~/.ssh is blocked by default" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  local blocked_section
  blocked_section=$(echo "$output" | sed -n '/Blocked directories/,/^$/p')
  [[ "$blocked_section" == *"$HOME/.ssh"* ]]
}

@test "dry-run: macOS blocks ~/Library" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(subpath \"$HOME/Library\")"* ]]
}

@test "dry-run: macOS does not auto-allow broad ~/Library subdirs" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" != *"carve-outs (read-write)"* ]]
  [[ "$output" != *"$HOME/Library/Application Support"* ]]
  [[ "$output" != *"$HOME/Library/Caches"* ]]
  [[ "$output" != *"$HOME/Library/Preferences"* ]]
}

@test "dry-run: macOS does not auto-allow ~/Library/Keychains" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" != *"carve-outs (read-only)"* ]]
  [[ "$output" != *"$HOME/Library/Keychains"* ]]
}

@test "dry-run: --allow explicitly opens a Library subtree" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local fake_home="$TEST_PROJECT/home"
  mkdir -p "$fake_home/Library/Caches"
  HOME="$fake_home" run "$SCODE" --dry-run --allow "$fake_home/Library/Caches" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  local fake_home_real
  fake_home_real="$(realpath "$fake_home")"
  [[ "$output" == *"(subpath \"$fake_home_real/Library\")"* ]]
  [[ "$output" == *"(subpath \"$fake_home_real/Library/Caches\")"* ]]
}

@test "dry-run: blocks privilege escalation" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run dry_run_cmd true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny process-exec (regex #"* ]]
  [[ "$output" == *"(sudo|su|login|doas|pkexec)"* ]]
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

@test "dry-run: --strict allows only the exact scode preload" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scode Node.js preload"* ]]
  [[ "$output" == *"(literal \""* ]]
  [[ "$output" == *"no-sandbox.js"* ]]
  [[ "$output" != *"scode lib directory"* ]]
}

@test "macOS runtime: strict project under a built-in blocked parent remains usable" {
  require_runtime_sandbox
  local fake_home="$TEST_PROJECT/strict-home-parent"
  local project="$fake_home/Documents/project"
  local empty_config="$fake_home/empty-config.yaml"
  mkdir -p "$project"
  : > "$empty_config"

  HOME="$fake_home" SCODE_CONFIG="$empty_config" run "$SCODE" --strict -C "$project" -- /bin/pwd
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(realpath "$project")"* ]]
}

@test "macOS runtime: strict executes an exact user-local binary" {
  require_runtime_sandbox
  local fake_home="$TEST_PROJECT/strict-home-bin"
  local project="$fake_home/project"
  local local_bin="$fake_home/.local/bin/test-tool"
  local empty_config="$fake_home/empty-config.yaml"
  mkdir -p "$project" "$(dirname "$local_bin")"
  : > "$empty_config"
  printf '#!/bin/bash\nprintf "LOCAL_BINARY_OK\\n"\n' > "$local_bin"
  chmod +x "$local_bin"

  HOME="$fake_home" SCODE_CONFIG="$empty_config" run "$SCODE" --strict -C "$project" -- "$local_bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCAL_BINARY_OK"* ]]
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

@test "dry-run: custom block covering project fails closed" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  # Create a project inside a blocked parent
  local blocked_parent="$TEST_PROJECT/blocked-parent"
  local project="$blocked_parent/myproject"
  mkdir -p "$project"
  local real_project
  real_project="$(realpath "$project")"
  run "$SCODE" --dry-run --block "$blocked_parent" -C "$project" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom block covers the project directory"* ]]
}

@test "dry-run: --ro does not weaken custom block covering project" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_parent="$TEST_PROJECT/blocked-parent-ro"
  local project="$blocked_parent/myproject"
  mkdir -p "$project"
  local real_project
  real_project="$(realpath "$project")"
  run "$SCODE" --dry-run --ro --block "$blocked_parent" -C "$project" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom block covers the project directory"* ]]
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
  [[ "$output" == *"doas"* ]]
  [[ "$output" == *"pkexec"* ]]
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

@test "dry-run: default mode --allow child of blocked parent emits allow AFTER deny" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_dir="$TEST_PROJECT/blocked-parent-default"
  local allow_dir="$TEST_PROJECT/blocked-parent-default/child"
  mkdir -p "$allow_dir"
  run "$SCODE" --dry-run --block "$blocked_dir" --allow "$allow_dir" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  local deny_pos allow_pos
  deny_pos=$(echo "$output" | grep -n "Blocked directories" | head -1 | cut -d: -f1)
  allow_pos=$(echo "$output" | grep -n "Explicitly allowed" | head -1 | cut -d: -f1)
  [ -n "$deny_pos" ]
  [ -n "$allow_pos" ]
  [ "$deny_pos" -lt "$allow_pos" ]
}

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

# ---------- Privilege escalation prevention regression ----------

@test "dry-run: privilege escalation uses regex not literal" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # Should use regex pattern instead of literal paths
  [[ "$output" == *'(deny process-exec (regex'* ]]
  [[ "$output" == *"sudo"* ]]
  [[ "$output" == *"pkexec"* ]]
  # Should NOT have the old literal form
  [[ "$output" != *'(deny process-exec (literal "/usr/bin/sudo"))'* ]]
}

@test "dry-run strict: privilege escalation uses regex" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *'(deny process-exec (regex'* ]]
  [[ "$output" != *'(deny process-exec (literal "/usr/bin/sudo"))'* ]]
}

@test "dry-run: sandbox-exec uses -- separator before command" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Command: true"* ]]
}

# ---------- Fix 3: CLI --block skips command-binary auto-allow ----------

@test "dry-run: CLI --block prevents command-binary auto-allow" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_dir="$TEST_PROJECT/blocked-bin"
  mkdir -p "$blocked_dir"
  local fake_tool="$blocked_dir/mytool"
  printf '#!/bin/bash\ntrue\n' > "$fake_tool"
  chmod +x "$fake_tool"
  run "$SCODE" --dry-run --block "$blocked_dir" -C "$TEST_PROJECT" -- "$fake_tool"
  [ "$status" -eq 0 ]
  # Should NOT contain auto-allow for the binary
  [[ "$output" != *"Command binary (auto-allow"* ]]
}

@test "dry-run: config block prevents command-binary auto-allow" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_dir="$TEST_PROJECT/config-blocked-bin"
  mkdir -p "$blocked_dir"
  local fake_tool="$blocked_dir/mytool"
  printf '#!/bin/bash\ntrue\n' > "$fake_tool"
  chmod +x "$fake_tool"
  local config_file="$TEST_PROJECT/block-config-autoallow.yaml"
  printf 'blocked:\n  - %s\n' "$blocked_dir" > "$config_file"
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- "$fake_tool"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Command binary (auto-allow"* ]]
}

# ---------- Fix 10: --block subdir inside project under blocked parent ----------

@test "dry-run: --block on project subdir remains denied" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local blocked_parent="/tmp/scode-fix10-parent-$$"
  track_cleanup "$blocked_parent"
  local project_dir="$blocked_parent/myproject"
  local secret_dir="$project_dir/secrets"
  mkdir -p "$secret_dir"
  run "$SCODE" --dry-run --block "$secret_dir" -C "$project_dir" -- true
  [ "$status" -eq 0 ]
  # The profile should re-deny the secrets subdir after the project allow
  [[ "$output" == *"(deny file-read* file-write* process-exec"* ]]
  [[ "$output" == *"secrets"* ]]
}

@test "runtime: --block on project subdir blocks access" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  require_runtime_sandbox
  local blocked_parent="/tmp/scode-fix10-rt-$$"
  track_cleanup "$blocked_parent"
  local project_dir="$blocked_parent/myproject"
  local secret_dir="$project_dir/secrets"
  mkdir -p "$secret_dir"
  echo "topsecret" > "$secret_dir/key.txt"
  # The command should fail to read the secret file
  run "$SCODE" --block "$secret_dir" -C "$project_dir" -- cat secrets/key.txt
  [ "$status" -ne 0 ]
  [[ "$output" != *"topsecret"* ]]
}

# ---------- P1: --block denies process-exec (not just file-read/write) ----------

@test "dry-run: --block includes process-exec in deny rule" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --block /tmp/exec-block-test -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny file-read* file-write* process-exec"* ]]
  [[ "$output" == *"/tmp/exec-block-test"* ]]
}

@test "dry-run: --strict --block includes process-exec in deny rule" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  run "$SCODE" --dry-run --strict --block /tmp/exec-block-strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny file-read* file-write* process-exec"* ]]
  [[ "$output" == *"/tmp/exec-block-strict"* ]]
}

@test "dry-run: --strict --allow includes process-exec in allow rule" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  local allow_dir="$TEST_PROJECT/exec-allow-strict"
  mkdir -p "$allow_dir"
  run "$SCODE" --dry-run --strict --allow "$allow_dir" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"(allow file-read* file-write* process-exec"* ]]
}

@test "runtime: --block prevents execution of blocked binary" {
  require_runtime_sandbox
  local blocked_dir="/tmp/scode-exec-block-$$"
  track_cleanup "$blocked_dir"
  mkdir -p "$blocked_dir"
  local fake_script="$blocked_dir/blocked-script.sh"
  printf '#!/bin/bash\necho SHOULD_NOT_PRINT\n' > "$fake_script"
  chmod +x "$fake_script"
  run "$SCODE" --block "$blocked_dir" -C "$TEST_PROJECT" -- "$fake_script"
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_PRINT"* ]]
}

@test "runtime: --strict --block prevents execution of blocked binary" {
  require_runtime_sandbox
  local blocked_dir="/tmp/scode-exec-block-strict-$$"
  track_cleanup "$blocked_dir"
  mkdir -p "$blocked_dir"
  local fake_script="$blocked_dir/blocked-script.sh"
  printf '#!/bin/bash\necho SHOULD_NOT_PRINT\n' > "$fake_script"
  chmod +x "$fake_script"
  run "$SCODE" --strict --block "$blocked_dir" -C "$TEST_PROJECT" -- "$fake_script"
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_PRINT"* ]]
}

@test "runtime: --block denies exec of binary under blocked path via bash -c" {
  require_runtime_sandbox
  local blocked_dir="/tmp/scode-exec-bash-$$"
  track_cleanup "$blocked_dir"
  mkdir -p "$blocked_dir"
  local fake_script="$blocked_dir/inner.sh"
  printf '#!/bin/bash\necho SHOULD_NOT_PRINT\n' > "$fake_script"
  chmod +x "$fake_script"
  # Execute via bash -c to test that the sandbox blocks the inner exec
  run "$SCODE" --block "$blocked_dir" -C "$TEST_PROJECT" -- bash -c "$fake_script"
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_PRINT"* ]]
}

# ---------- Filesystem pattern rules (filesystem: config section) ----------

@test "filesystem: none rule emits deny after allows, before ro cap" {
  local config_file="$TEST_PROJECT/fs-rules.yaml"
  cat > "$config_file" <<YAML
filesystem:
  "~/**/.env": none
  "~/**/.envrc": none
YAML
  run "$SCODE" --dry-run --config "$config_file" --ro -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  grep -qF '; Filesystem pattern rules' <<<"$output"
  grep -qF '(deny file-read* file-write* process-exec' <<<"$output"
  grep -qF "regex #\"^$HOME/.*\\.env\$\"" <<<"$output"
  grep -qF "regex #\"^$HOME/.*\\.envrc\$\"" <<<"$output"
  local fs_pos ro_pos
  fs_pos=$(grep -nF '; Filesystem pattern rules' <<<"$output" | cut -d: -f1)
  ro_pos=$(grep -nF '; Final read-only project invariant' <<<"$output" | cut -d: -f1)
  [ -n "$fs_pos" ]
  [ -n "$ro_pos" ]
  [ "$fs_pos" -lt "$ro_pos" ]
}

@test "filesystem: read and write modes emit correct rules" {
  local config_file="$TEST_PROJECT/fs-rules-modes.yaml"
  cat > "$config_file" <<YAML
filesystem:
  "cache": read
  "build": write
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  # read mode: allow reads, deny writes
  grep -qF '(allow file-read* process-exec' <<<"$output"
  grep -qF '(deny file-write*' <<<"$output"
  grep -qF '/cache$"' <<<"$output"
  # write mode: allow read-write
  grep -qF '(allow file-read* file-write*' <<<"$output"
  grep -qF '/build$"' <<<"$output"
}

@test "filesystem: later rule narrows earlier rule (order preserved)" {
  local config_file="$TEST_PROJECT/fs-rules-order.yaml"
  cat > "$config_file" <<YAML
filesystem:
  "~/**/.env": none
  "~/keep/.env": write
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  local deny_pos allow_pos
  deny_pos=$(grep -nF "regex #\"^$HOME/.*\\.env\$\"" <<<"$output" | cut -d: -f1)
  allow_pos=$(grep -nF "regex #\"^$HOME/keep/\\.env\$\"" <<<"$output" | cut -d: -f1)
  [ -n "$deny_pos" ]
  [ -n "$allow_pos" ]
  [ "$deny_pos" -lt "$allow_pos" ]
}

@test "filesystem: invalid mode is rejected" {
  local config_file="$TEST_PROJECT/fs-rules-bad-mode.yaml"
  cat > "$config_file" <<YAML
filesystem:
  "~/**/.env": sometimes
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 'none', 'read', or 'write'"* ]]
}

@test "filesystem: unsupported pattern characters are rejected" {
  local config_file="$TEST_PROJECT/fs-rules-bad-pattern.yaml"
  cat > "$config_file" <<YAML
filesystem:
  "~/**/.env[rc]": none
YAML
  run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported filesystem rule pattern"* ]]
}

@test "filesystem: project config may only deny" {
  local proj
  proj="$(mktemp -d)"
  cat > "$proj/.scode.yaml" <<YAML
filesystem:
  "secret": none
  "writable": write
YAML
  run "$SCODE" --dry-run -C "$proj" -- true
  [ "$status" -eq 0 ]
  grep -qF '/secret$"' <<<"$output"
  ! grep -qF '/writable$"' <<<"$output"
  [[ "$output" == *"restrictive-only"* ]]
  rm -rf "$proj"
}

@test "filesystem: log header records fsrule metadata" {
  require_runtime_sandbox
  local proj log_file
  proj="$(mktemp -d)"
  echo "s3cret" > "$proj/.envrc"
  cat > "$proj/.scode.yaml" <<YAML
filesystem:
  "**/.envrc": none
YAML
  log_file="$proj/scode.log"
  run "$SCODE" --log "$log_file" -C "$proj" -- cat .envrc
  [ "$status" -ne 0 ]
  [ -f "$log_file" ]
  grep -q '# fsrule: project .*\*\*/.envrc -> none' "$log_file"
  grep -qF '"fsrules":[{"mode":"none","regex":"' "$log_file"
  rm -rf "$proj"
}

@test "macOS runtime: filesystem none rule denies nested .envrc reads" {
  require_runtime_sandbox
  local config_file="$TEST_PROJECT/fs-rules-runtime.yaml"
  mkdir -p "$TEST_PROJECT/fs-nested"
  echo "dotenv-secret" > "$TEST_PROJECT/fs-nested/.envrc"
  cat > "$config_file" <<YAML
filesystem:
  "**/.envrc": none
YAML
  run "$SCODE" --config "$config_file" -C "$TEST_PROJECT" -- cat "$TEST_PROJECT/fs-nested/.envrc"
  [ "$status" -ne 0 ]
  [[ "$output" != *"dotenv-secret"* ]]
}

@test "macOS runtime: filesystem write rule allows writes in carve-out" {
  require_runtime_sandbox
  local config_file="$TEST_PROJECT/fs-rules-rw.yaml"
  mkdir -p "$TEST_PROJECT/fs-build"
  cat > "$config_file" <<YAML
filesystem:
  "fs-build": write
YAML
  run "$SCODE" --config "$config_file" -C "$TEST_PROJECT" -- sh -c "echo ok > $TEST_PROJECT/fs-build/out.txt"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT/fs-build/out.txt" ]
  [[ "$(cat "$TEST_PROJECT/fs-build/out.txt")" == "ok" ]]
}

@test "macOS runtime: filesystem none rule blocks read even with --allow" {
  require_runtime_sandbox
  local config_file="$TEST_PROJECT/fs-rules-allow.yaml"
  mkdir -p "$TEST_PROJECT/fs-allowdir"
  echo "keep" > "$TEST_PROJECT/fs-allowdir/.env"
  cat > "$config_file" <<YAML
filesystem:
  "**/.env": none
YAML
  # --allow cannot reopen a filesystem rule; the .env deny must still win
  run "$SCODE" --config "$config_file" --allow "$TEST_PROJECT/fs-allowdir" -C "$TEST_PROJECT" -- cat "$TEST_PROJECT/fs-allowdir/.env"
  [ "$status" -ne 0 ]
  [[ "$output" != *"keep"* ]]
}
