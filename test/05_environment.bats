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

# A stub on PATH stands in for harnesses the test host may not have
# installed; scode resolves the command through the caller's PATH.
make_stub_harness() {
  local stub_dir="$TEST_PROJECT/stub-bin"
  mkdir -p "$stub_dir"
  printf '#!/bin/sh\nexit 0\n' > "$stub_dir/$1"
  chmod +x "$stub_dir/$1"
}

@test "agy shortcut produces no warning" {
  make_stub_harness agy
  PATH="$TEST_PROJECT/stub-bin:$PATH" run "$SCODE" --dry-run -C "$TEST_PROJECT" agy
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

@test "--scrub-env removes routed-provider and harness credential vars" {
  export ZAI_API_KEY="zai"
  export ZHIPU_API_KEY="zhipu"
  export MOONSHOT_API_KEY="moonshot"
  export KIMI_API_KEY="kimi"
  export KIMI_MODEL_API_KEY="kimi-model"
  export DASHSCOPE_API_KEY="dashscope"
  export QWEN_API_KEY="qwen"
  export ANTHROPIC_AUTH_TOKEN="anthropic-auth"
  export CLAUDE_CODE_OAUTH_TOKEN="claude-oauth"
  export CODEX_API_KEY="codex"
  export COPILOT_GITHUB_TOKEN="copilot-gh"
  export CURSOR_API_KEY="cursor"
  export FACTORY_API_KEY="factory"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"scrubbed env vars"* ]]
  [[ "$output" == *"ZAI_API_KEY"* ]]
  [[ "$output" == *"ZHIPU_API_KEY"* ]]
  [[ "$output" == *"MOONSHOT_API_KEY"* ]]
  [[ "$output" == *"KIMI_API_KEY"* ]]
  [[ "$output" == *"KIMI_MODEL_API_KEY"* ]]
  [[ "$output" == *"DASHSCOPE_API_KEY"* ]]
  [[ "$output" == *"QWEN_API_KEY"* ]]
  [[ "$output" == *"ANTHROPIC_AUTH_TOKEN"* ]]
  [[ "$output" == *"CLAUDE_CODE_OAUTH_TOKEN"* ]]
  [[ "$output" == *"CODEX_API_KEY"* ]]
  [[ "$output" == *"COPILOT_GITHUB_TOKEN"* ]]
  [[ "$output" == *"CURSOR_API_KEY"* ]]
  [[ "$output" == *"FACTORY_API_KEY"* ]]
  unset ZAI_API_KEY ZHIPU_API_KEY MOONSHOT_API_KEY KIMI_API_KEY KIMI_MODEL_API_KEY \
    DASHSCOPE_API_KEY QWEN_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN \
    CODEX_API_KEY COPILOT_GITHUB_TOKEN CURSOR_API_KEY FACTORY_API_KEY
}

@test "--scrub-env leaves provider configuration variables alone" {
  # Configuration, not credentials: the channels provider overrides use to
  # point a harness at a gateway, plus a synthetic marker standing in for any
  # non-credential value. Only credential-bearing names are scrubbed (covered
  # by the scrub tests above); a test must never assert that a name ending in
  # API_KEY survives the scrub.
  export OPENAI_API_BASE="https://gw.example/v1"
  export LLM_BASE_URL="https://gw.example/v1"
  export LLM_MODEL="glm-5.3"
  export GOOSE_PROVIDER="openai"
  export GOOSE_MODEL="glm-5.3"
  export KIMI_MODEL_BASE_URL="https://gw.example/v1"
  export KIMI_MODEL_MAX_COMPLETION_TOKENS="4096"
  export PI_CODING_AGENT_DIR="$TEST_PROJECT/pi-agent"
  export OPENCODE_CONFIG="$TEST_PROJECT/opencode.json"
  export CURSOR_API_ENDPOINT="https://gw.example"
  export ANTHROPIC_BASE_URL="https://gw.example"
  export SCRUB_BOUNDARY_MARKER="not-a-credential"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"OPENAI_API_BASE"* ]]
  [[ "$output" != *"LLM_BASE_URL"* ]]
  [[ "$output" != *"LLM_MODEL"* ]]
  [[ "$output" != *"GOOSE_PROVIDER"* ]]
  [[ "$output" != *"GOOSE_MODEL"* ]]
  [[ "$output" != *"KIMI_MODEL_BASE_URL"* ]]
  [[ "$output" != *"KIMI_MODEL_MAX_COMPLETION_TOKENS"* ]]
  [[ "$output" != *"PI_CODING_AGENT_DIR"* ]]
  [[ "$output" != *"OPENCODE_CONFIG"* ]]
  [[ "$output" != *"CURSOR_API_ENDPOINT"* ]]
  [[ "$output" != *"ANTHROPIC_BASE_URL"* ]]
  [[ "$output" != *"SCRUB_BOUNDARY_MARKER"* ]]
  unset OPENAI_API_BASE LLM_BASE_URL LLM_MODEL GOOSE_PROVIDER GOOSE_MODEL \
    KIMI_MODEL_BASE_URL KIMI_MODEL_MAX_COMPLETION_TOKENS PI_CODING_AGENT_DIR \
    OPENCODE_CONFIG CURSOR_API_ENDPOINT ANTHROPIC_BASE_URL SCRUB_BOUNDARY_MARKER
}

@test "--scrub-env does not scrub codemux override control variables" {
  # CODEMUX_*_PROVIDER_* routing settings are how codemux points a run at an
  # endpoint; scrubbing them would cut the sandboxed child off from the
  # override codemux configured for it. Only the non-credential routing names
  # are asserted here; credential names belong to the scrub tests.
  export CODEMUX_AIDER_PROVIDER_BASE_URL="https://gw.example/v1"
  export CODEMUX_KIMI_PROVIDER_MODEL="glm-5.3"
  run "$SCODE" --dry-run --scrub-env -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"CODEMUX_AIDER_PROVIDER_BASE_URL"* ]]
  [[ "$output" != *"CODEMUX_KIMI_PROVIDER_MODEL"* ]]
  unset CODEMUX_AIDER_PROVIDER_BASE_URL CODEMUX_KIMI_PROVIDER_MODEL
}

# ---------- --keep-env ----------

@test "--keep-env exempts a name from the scrub in the child environment" {
  require_runtime_sandbox
  # stdout alone: stderr carries scode's own warnings (unknown harness, the
  # list of scrubbed names on this host), which must not fold into the value.
  ZAI_API_KEY="kept-value" run --separate-stderr "$SCODE" --scrub-env --keep-env ZAI_API_KEY \
    -C "$TEST_PROJECT" -- printenv ZAI_API_KEY
  [ "$status" -eq 0 ]
  [[ "$output" == "kept-value" ]]
}

@test "--keep-env exempts only the named names" {
  require_runtime_sandbox
  ZAI_API_KEY="a" QWEN_API_KEY="b" OPENAI_API_KEY="c" run \
    "$SCODE" --scrub-env --keep-env ZAI_API_KEY,QWEN_API_KEY \
    -C "$TEST_PROJECT" -- env
  [ "$status" -eq 0 ]
  [[ "$output" == *"ZAI_API_KEY=a"* ]]
  [[ "$output" == *"QWEN_API_KEY=b"* ]]
  [[ "$output" != *"OPENAI_API_KEY=c"* ]]
}

@test "--keep-env is repeatable and deduplicates" {
  run "$SCODE" --dry-run --scrub-env --keep-env ZAI_API_KEY --keep-env ZAI_API_KEY \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--keep-env: ZAI_API_KEY"* ]]
  [[ "$(echo "$output" | grep -c 'keep-env:')" -eq 1 ]]
}

@test "--keep-env refuses names containing =" {
  run "$SCODE" --dry-run --scrub-env --keep-env "ZAI_API_KEY=secret" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid --keep-env name"* ]]
}

@test "--keep-env refuses names containing whitespace" {
  run "$SCODE" --dry-run --scrub-env --keep-env "ZAI API_KEY" \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid --keep-env name"* ]]
}

@test "--keep-env refuses empty list entries" {
  # Middle, trailing, and leading commas are all empty entries. The trailing
  # case regressed first: field splitting dropped it, so `NAME,` was accepted.
  local raw
  for raw in "ZAI_API_KEY,," "ZAI_API_KEY," ",ZAI_API_KEY" ","; do
    run "$SCODE" --dry-run --scrub-env --keep-env "$raw" \
      -C "$TEST_PROJECT" -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid --keep-env list: empty entry"* ]]
  done
}

@test "--keep-env never expands glob patterns against the working directory" {
  # `AWS_*` is not a variable name. If the split went through pathname
  # expansion, a file named AWS_notes in the working directory would replace
  # the pattern and silently exempt a variable nobody named.
  local glob_dir="$TEST_PROJECT/keep-env-glob"
  mkdir -p "$glob_dir"
  touch "$glob_dir/AWS_notes"
  cd "$glob_dir"
  run "$SCODE" --dry-run --scrub-env --keep-env 'AWS_*' \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid --keep-env name"* ]]
}

@test "--keep-env refuses startup-injection and loader names" {
  # The scrub removes these because they inject code or configuration into
  # every child process; keep-env is for credentials a launcher injects on
  # purpose, so they can never be exempted. The error prints the refused set.
  local name
  for name in NODE_OPTIONS BASH_ENV ENV ZDOTDIR PYTHONPATH PYTHONHOME RUBYOPT \
              PERL5OPT PERL5LIB PERLLIB JAVA_TOOL_OPTIONS _JAVA_OPTIONS \
              LD_PRELOAD DYLD_INSERT_LIBRARIES GIT_CONFIG_GLOBAL GIT_ASKPASS \
              SSH_AUTH_SOCK; do
    run "$SCODE" --dry-run --scrub-env --keep-env "$name" \
      -C "$TEST_PROJECT" -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"--keep-env refuses '${name}'"* ]]
    [[ "$output" == *"refused names and prefixes: LD_"* ]]
  done
}

@test "--keep-env missing argument fails" {
  run "$SCODE" --dry-run --scrub-env --keep-env
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
}

@test "--keep-env prints kept names in dry-run output" {
  run "$SCODE" --dry-run --scrub-env --keep-env ZAI_API_KEY,QWEN_API_KEY \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--keep-env: ZAI_API_KEY QWEN_API_KEY"* ]]
}

@test "--keep-env dry-run prints names only, never values" {
  ZAI_API_KEY="secret-value" run "$SCODE" --dry-run --scrub-env \
    --keep-env ZAI_API_KEY -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--keep-env: ZAI_API_KEY"* ]]
  [[ "$output" != *"secret-value"* ]]
}

@test "--keep-env without --scrub-env warns that it has no effect" {
  run "$SCODE" --dry-run --keep-env ZAI_API_KEY -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--keep-env has no effect without --scrub-env"* ]]
}

@test "--keep-env no-effect warning stays silent when config enables scrub" {
  local user_config
  user_config="$(mktemp)"
  printf 'scrub_env: true\n' > "$user_config"
  run "$SCODE" --dry-run --config "$user_config" --keep-env ZAI_API_KEY \
    -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"has no effect without --scrub-env"* ]]
  [[ "$output" == *"scrub-env active"* ]]
  rm -f "$user_config"
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

@test "--scrub-env strips LLM_API_KEY and --keep-env keeps it (review sc4)" {
  require_runtime_sandbox
  LLM_API_KEY="secret-marker" run --separate-stderr "$SCODE" --scrub-env \
    -C "$TEST_PROJECT" -- sh -c 'printf "%s" "${LLM_API_KEY:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == "unset" ]]
  LLM_API_KEY="secret-marker" run --separate-stderr "$SCODE" --scrub-env --keep-env LLM_API_KEY \
    -C "$TEST_PROJECT" -- sh -c 'printf "%s" "${LLM_API_KEY:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == "secret-marker" ]]
}

@test "--keep-env refusal lists the refused names separated by spaces (review sc4)" {
  run "$SCODE" --scrub-env --keep-env NODE_OPTIONS -C "$TEST_PROJECT" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"refused names and prefixes:"* ]]
  [[ "$output" != *"refused names and prefixes:"*","* ]]
}
