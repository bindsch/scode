#!/usr/bin/env bats
# Environment variables — scrubbing, overrides, browser env

load test_helper

# ---------- Browser double-sandbox prevention ----------

@test "exports SCODE_SANDBOXED=1 inside sandbox" {
  require_runtime_sandbox
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- printenv SCODE_SANDBOXED 2>/dev/null)
  [[ "$val" == "1" ]]
}

@test "exports ELECTRON_DISABLE_SANDBOX=1 inside sandbox" {
  require_runtime_sandbox
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- printenv ELECTRON_DISABLE_SANDBOX 2>/dev/null)
  [[ "$val" == "1" ]]
}

@test "exports PLAYWRIGHT_MCP_NO_SANDBOX=1 inside sandbox" {
  require_runtime_sandbox
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- printenv PLAYWRIGHT_MCP_NO_SANDBOX 2>/dev/null)
  [[ "$val" == "1" ]]
}

@test "appends --no-sandbox to CHROMIUM_FLAGS inside sandbox" {
  require_runtime_sandbox
  run "$SCODE" -C "$TEST_PROJECT" -- printenv CHROMIUM_FLAGS
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-sandbox"* ]]
}

@test "preserves existing CHROMIUM_FLAGS when appending" {
  require_runtime_sandbox
  CHROMIUM_FLAGS="--existing-flag" run "$SCODE" -C "$TEST_PROJECT" -- printenv CHROMIUM_FLAGS
  [ "$status" -eq 0 ]
  [[ "$output" == *"--existing-flag"* ]]
  [[ "$output" == *"--no-sandbox"* ]]
}

@test "similar CHROMIUM_FLAGS token does not suppress --no-sandbox" {
  CHROMIUM_FLAGS="--no-sandbox-test" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHROMIUM_FLAGS=--no-sandbox-test --no-sandbox"* ]]
}

@test "sets NODE_OPTIONS with no-sandbox preload" {
  require_runtime_sandbox
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- printenv NODE_OPTIONS 2>/dev/null)
  [[ "$val" == *"no-sandbox.js"* ]]
}

@test "NODE_OPTIONS uses --require= form (safe with spaces)" {
  require_runtime_sandbox
  local val
  val=$("$SCODE" -C "$TEST_PROJECT" -- printenv NODE_OPTIONS 2>/dev/null)
  [[ "$val" == *"--require="* ]]
}

@test "preserves existing NODE_OPTIONS when adding preload" {
  require_runtime_sandbox
  NODE_OPTIONS="--max-old-space-size=2048" run "$SCODE" -C "$TEST_PROJECT" -- printenv NODE_OPTIONS
  [ "$status" -eq 0 ]
  [[ "$output" == *"--max-old-space-size=2048"* ]]
  [[ "$output" == *"--require="* ]]
  [[ "$output" == *"no-sandbox.js"* ]]
}

# ---------- Environment scrubbing ----------

@test "--scrub-env removes sensitive vars" {
  OPENAI_API_KEY="test-key-12345" run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scrubbed env vars"* ]]
  [[ "$output" == *"OPENAI_API_KEY"* ]]
}

@test "--scrub-env covers all documented token patterns" {
  export AWS_ACCESS_KEY_ID="akid"
  export OPENAI_API_KEY="openai"
  export ANTHROPIC_API_KEY="anthropic"
  export GITHUB_TOKEN="gh"
  export GH_TOKEN="gh-cli"
  export GITLAB_PAT_TOKEN="gitlab"
  export GOOGLE_APPLICATION_CREDENTIALS="/tmp/gcp.json"
  export AZURE_CLIENT_SECRET="azure"
  export DO_API_KEY="do"
  export HF_TOKEN="hf"
  export HUGGING_FACE_HUB_TOKEN="hfhub"
  export COHERE_API_KEY="cohere"
  export MISTRAL_API_KEY="mistral"
  export REPLICATE_API_TOKEN="replicate"
  export TOGETHER_API_KEY="together"
  export GROQ_API_KEY="groq"
  export FIREWORKS_API_KEY="fireworks"
  export DEEPSEEK_API_KEY="deepseek"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"AWS_ACCESS_KEY_ID"* ]]
  [[ "$output" == *"OPENAI_API_KEY"* ]]
  [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
  [[ "$output" == *"GITHUB_TOKEN"* ]]
  [[ "$output" == *"GH_TOKEN"* ]]
  [[ "$output" == *"GITLAB_PAT_TOKEN"* ]]
  [[ "$output" == *"GOOGLE_APPLICATION_CREDENTIALS"* ]]
  [[ "$output" == *"AZURE_CLIENT_SECRET"* ]]
  [[ "$output" == *"DO_API_KEY"* ]]
  [[ "$output" == *"HF_TOKEN"* ]]
  [[ "$output" == *"HUGGING_FACE_HUB_TOKEN"* ]]
  [[ "$output" == *"COHERE_API_KEY"* ]]
  [[ "$output" == *"MISTRAL_API_KEY"* ]]
  [[ "$output" == *"REPLICATE_API_TOKEN"* ]]
  [[ "$output" == *"TOGETHER_API_KEY"* ]]
  [[ "$output" == *"GROQ_API_KEY"* ]]
  [[ "$output" == *"FIREWORKS_API_KEY"* ]]
  [[ "$output" == *"DEEPSEEK_API_KEY"* ]]
  unset AWS_ACCESS_KEY_ID OPENAI_API_KEY ANTHROPIC_API_KEY GITHUB_TOKEN GH_TOKEN \
    GITLAB_PAT_TOKEN GOOGLE_APPLICATION_CREDENTIALS AZURE_CLIENT_SECRET DO_API_KEY \
    HF_TOKEN HUGGING_FACE_HUB_TOKEN COHERE_API_KEY MISTRAL_API_KEY \
    REPLICATE_API_TOKEN TOGETHER_API_KEY GROQ_API_KEY FIREWORKS_API_KEY \
    DEEPSEEK_API_KEY
}

@test "--scrub-env removes sensitive vars from child process environment" {
  require_runtime_sandbox
  OPENAI_API_KEY="runtime-secret-value" run "$SCODE" --scrub-env -C "$TEST_PROJECT" -- env
  [ "$status" -eq 0 ]
  [[ "$output" != *"OPENAI_API_KEY=runtime-secret-value"* ]]
}

@test "--scrub-env ignores multiline value fragments that look like env keys" {
  local crafted_value
  crafted_value=$'line1\nAWS_FAKE=from-value-fragment'
  OPENAI_API_KEY="$crafted_value" run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPENAI_API_KEY"* ]]
  [[ "$output" != *"AWS_FAKE"* ]]
}

# ---------- Known harness shortcuts ----------

@test "known harness produces no warning" {
  # 'claude' is a known harness and should be on PATH
  command -v claude >/dev/null 2>&1 || skip "claude not installed"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"not a known harness"* ]]
}

@test "known harness path produces no warning" {
  local harness_path="$TEST_PROJECT/bin/claude"
  run "$SCODE" --dry-run -C "$TEST_PROJECT" "$harness_path"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not a known harness"* ]]
}

@test "known harness behind wrapper produces no warning" {
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- env claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"not a known harness"* ]]
}

@test "unknown command warns about untested harness" {
  run "$SCODE" --dry-run -C "$TEST_PROJECT" -- ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a known harness"* ]]
}

@test "unknown command still runs" {
  local platform
  for platform in darwin linux; do
    _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Command: true"* || "$output" == *" -- true"* ]]
  done
}

# ---------- Environment variable overrides ----------

@test "SCODE_NET=off disables network" {
  local platform
  for platform in darwin linux; do
    SCODE_NET=off _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
  done
}

@test "SCODE_FS_MODE=ro makes project read-only" {
  local platform
  for platform in darwin linux; do
    SCODE_FS_MODE=ro _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_project_read_only_output "$output" "$TEST_PROJECT"
  done
}

@test "CLI --no-net overrides SCODE_NET=on" {
  local platform
  for platform in darwin linux; do
    SCODE_NET=on _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --no-net -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_network_disabled_output "$output"
  done
}

@test "CLI --ro overrides SCODE_FS_MODE=rw" {
  local platform
  for platform in darwin linux; do
    SCODE_FS_MODE=rw _SCODE_PLATFORM="$platform" run "$SCODE" --dry-run --ro -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    assert_project_read_only_output "$output" "$TEST_PROJECT"
  done
}

# ---------- Wildcard scrub patterns ----------

@test "--scrub-env scrubs wildcard patterns (AWS_*)" {
  export AWS_ACCESS_KEY_ID="test-key"
  export AWS_SECRET_ACCESS_KEY="test-secret"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scrubbed env vars"* ]]
  [[ "$output" == *"AWS_ACCESS_KEY_ID"* ]]
  [[ "$output" == *"AWS_SECRET_ACCESS_KEY"* ]]
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

# ---------- Additional scrub patterns ----------

@test "--scrub-env scrubs AI/ML tokens" {
  export HF_TOKEN="test-hf-token"
  export DEEPSEEK_API_KEY="test-ds-key"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scrubbed env vars"* ]]
  [[ "$output" == *"HF_TOKEN"* ]]
  [[ "$output" == *"DEEPSEEK_API_KEY"* ]]
  unset HF_TOKEN DEEPSEEK_API_KEY
}

# ---------- New scrub patterns ----------

@test "--scrub-env scrubs newly added token patterns" {
  export VAULT_TOKEN="vault-test"
  export NPM_TOKEN="npm-test"
  export VERCEL_TOKEN="vercel-test"
  export CLOUDFLARE_API_TOKEN="cf-test"
  export DOCKER_PASSWORD="docker-test"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAULT_TOKEN"* ]]
  [[ "$output" == *"NPM_TOKEN"* ]]
  [[ "$output" == *"VERCEL_TOKEN"* ]]
  [[ "$output" == *"CLOUDFLARE_API_TOKEN"* ]]
  [[ "$output" == *"DOCKER_PASSWORD"* ]]
  unset VAULT_TOKEN NPM_TOKEN VERCEL_TOKEN CLOUDFLARE_API_TOKEN DOCKER_PASSWORD
}

@test "--scrub-env scrubs remaining documented token patterns" {
  export NETLIFY_AUTH_TOKEN="netlify-test"
  export PULUMI_ACCESS_TOKEN="pulumi-test"
  export SENTRY_AUTH_TOKEN="sentry-test"
  export SNYK_TOKEN="snyk-test"
  export DOCKER_AUTH_CONFIG='{"auths":{"example.com":{"auth":"abc"}}}'
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"NETLIFY_AUTH_TOKEN"* ]]
  [[ "$output" == *"PULUMI_ACCESS_TOKEN"* ]]
  [[ "$output" == *"SENTRY_AUTH_TOKEN"* ]]
  [[ "$output" == *"SNYK_TOKEN"* ]]
  [[ "$output" == *"DOCKER_AUTH_CONFIG"* ]]
  unset NETLIFY_AUTH_TOKEN PULUMI_ACCESS_TOKEN SENTRY_AUTH_TOKEN SNYK_TOKEN DOCKER_AUTH_CONFIG
}

# ---------- SSH scrub patterns ----------

@test "SSH agent variables are removed before optional scrubbing" {
  export SSH_AUTH_SOCK="/tmp/ssh-agent.sock"
  export SSH_AGENT_PID="12345"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"/tmp/ssh-agent.sock"* ]]
  [[ "$output" != *"12345"* ]]
  unset SSH_AUTH_SOCK SSH_AGENT_PID
}

@test "SSH agent socket is blocked by default and requires double opt-in" {
  require_node
  require_any_runtime_sandbox
  local socket_path="$TEST_PROJECT/agent.sock"
  local ready_file="$TEST_PROJECT/agent.ready"
  node -e '
    const fs = require("fs");
    const net = require("net");
    const server = net.createServer(socket => socket.end("AGENT_OK\n"));
    server.listen(process.argv[1], () => fs.writeFileSync(process.argv[2], "ready"));
  ' "$socket_path" "$ready_file" &
  local server_pid=$!
  local i
  for i in $(seq 1 100); do
    [[ -S "$socket_path" && -f "$ready_file" ]] && break
    sleep 0.02
  done
  [[ -S "$socket_path" ]]

  local platform
  for platform in darwin linux; do
    SSH_AUTH_SOCK="$socket_path" _SCODE_PLATFORM="$platform" run \
      "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"$socket_path"* ]]
    if [[ "$platform" == "linux" ]]; then
      [[ "$output" == *"--ro-bind /dev/null"* ]]
    fi
  done

  SSH_AUTH_SOCK="$socket_path" run "$SCODE" -C "$TEST_PROJECT" -- \
    /bin/bash -c 'test -z "${SSH_AUTH_SOCK:-}"'
  [ "$status" -eq 0 ]

  SSH_AUTH_SOCK="$socket_path" run "$SCODE" --allow "$socket_path" -C "$TEST_PROJECT" -- \
    env SSH_AUTH_SOCK="$socket_path" node -e '
      const net = require("net");
      const socket = net.connect(process.env.SSH_AUTH_SOCK);
      socket.on("data", data => process.stdout.write(data));
      socket.on("error", error => { console.error(error.code); process.exit(12); });
    '
  local connect_status=$status
  local connect_output="$output"
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  [ "$connect_status" -eq 0 ]
  [[ "$connect_output" == *"AGENT_OK"* ]]
}

@test "sandboxed command does not inherit nonstandard caller descriptors" {
  [[ -n "${SCODE_COVERAGE_TARGET:-}" ]] && skip "coverage harness requires its own descriptor"
  require_any_runtime_sandbox
  local descriptor_file="$TEST_PROJECT/inherited-fd-secret"
  printf 'descriptor-secret\n' > "$descriptor_file"
  exec 7<"$descriptor_file"
  run "$SCODE" -C "$TEST_PROJECT" -- /bin/bash -c '
    if { : <&7; } 2>/dev/null; then
      echo FD_STILL_OPEN
      exit 9
    fi
    echo FD_CLOSED
  '
  local child_status=$status
  local child_output="$output"
  exec 7<&-
  [ "$child_status" -eq 0 ]
  [[ "$child_output" == *"FD_CLOSED"* ]]
  [[ "$child_output" != *"FD_STILL_OPEN"* ]]
}

@test "--scrub-env removes current provider, package, and startup-injection vars" {
  export XAI_API_KEY="xai-secret"
  export GEMINI_API_KEY="gemini-secret"
  export OPENROUTER_API_KEY="openrouter-secret"
  export NODE_AUTH_TOKEN="npm-secret"
  export CARGO_REGISTRY_TOKEN="cargo-secret"
  export BASH_ENV="/tmp/hostile-bash-env"
  export NODE_OPTIONS="--require=/tmp/hostile.js"
  export GIT_CONFIG_COUNT="1"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"XAI_API_KEY"* ]]
  [[ "$output" == *"GEMINI_API_KEY"* ]]
  [[ "$output" == *"OPENROUTER_API_KEY"* ]]
  [[ "$output" == *"NODE_AUTH_TOKEN"* ]]
  [[ "$output" == *"CARGO_REGISTRY_TOKEN"* ]]
  # BASH_ENV is removed before any child shell starts, so it is absent even
  # from the later scrub summary.
  [[ "$output" != *"hostile-bash-env"* ]]
  [[ "$output" == *"NODE_OPTIONS"* ]]
  [[ "$output" == *"GIT_CONFIG_COUNT"* ]]
  unset XAI_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY NODE_AUTH_TOKEN
  unset CARGO_REGISTRY_TOKEN BASH_ENV NODE_OPTIONS GIT_CONFIG_COUNT
}

@test "grok defense pins collection controls even for nested launches" {
  local config_file="$TEST_PROJECT/grok-defense-env.yaml"
  cat > "$config_file" <<'YAML'
grok_defense: true
YAML

  GROK_TELEMETRY_ENABLED=true \
  GROK_TELEMETRY_TRACE_UPLOAD=true \
  GROK_WORKSPACE_DATA_COLLECTION_DISABLED=false \
    run "$SCODE" --dry-run --config "$config_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"GROK_TELEMETRY_ENABLED=false"* ]]
  [[ "$output" == *"GROK_TELEMETRY_TRACE_UPLOAD=false"* ]]
  [[ "$output" == *"GROK_WORKSPACE_DATA_COLLECTION_DISABLED=true"* ]]
  [[ "$output" == *"GROK_WORKSPACE_UPLOAD_QUEUE_ENABLED=false"* ]]
  [[ "$output" == *"GROK_RELAY_SYNC_ENABLED=false"* ]]
  [[ "$output" == *"GROK_RESPECT_GITIGNORE=1"* ]]
  [[ "$output" == *"GROK_DISABLE_AUTOUPDATER=1"* ]]
}

# ---------- Portable date format in log ----------

@test "--log writes ISO-like timestamp" {
  require_runtime_sandbox
  local log_file="$TEST_PROJECT/date-test.log"
  run "$SCODE" --log "$log_file" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  # Verify timestamp format is YYYY-MM-DDTHH:MM:SS
  grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$log_file"
}
