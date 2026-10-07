#!/usr/bin/env bats
# Claude Code Keychain credential sync (macOS only).
#
# The sync runs in the parent process right before sandbox-exec, so the runtime
# cases launch a real sandbox around a fake `claude` and inspect a fake home
# from outside. scode pins PATH to the system directories before doing
# anything, so `security` cannot be shadowed by a test double: the copy itself
# needs a real Keychain item and is verified by hand, as do the refusals
# (a refresh token in the file while a Keychain item exists is never launched
# through). What can be checked without one is the three guards that decline
# the copy and say so on stderr (a wrapper, a harness inside the project, a
# ~/.claude inside the project), the opt-out flag, and the file-only-login
# exception: with no Keychain item (a fake HOME has none) a refresh token in
# the file is Claude Code's own and the launch proceeds with it untouched. The guards that return silently (--dry-run, --trust
# untrusted, a --block over ~/.claude, no ~/.claude at all) leave nothing to
# observe without a Keychain item, so they are not asserted here.

load test_helper

setup() {
  TEST_PROJECT="$(mktemp -d)"
  _EXTRA_CLEANUP_DIRS=()
  unset SCODE_CONFIG SCODE_NET SCODE_FS_MODE

  # The harness lives outside the project: a `claude` inside it is refused.
  TOOLS="$(mktemp -d)"
  track_cleanup "$TOOLS"
  FAKE_HOME="$TOOLS/home"
  PROJECT="$TEST_PROJECT/project"
  EMPTY_CONFIG="$TOOLS/empty-config.yaml"
  mkdir -p "$FAKE_HOME/.claude" "$PROJECT" "$TOOLS/bin"
  : > "$EMPTY_CONFIG"
  printf '#!/bin/bash\nprintf "CLAUDE_OK\\n"\n' > "$TOOLS/bin/claude"
  chmod +x "$TOOLS/bin/claude"
}

run_scode() {
  HOME="$FAKE_HOME" SCODE_CONFIG="$EMPTY_CONFIG" PATH="$TOOLS/bin:$PATH" \
    run "$SCODE" "$@"
}

@test "credential sync: --no-credential-sync is accepted and the harness still runs" {
  require_runtime_sandbox
  run_scode --no-credential-sync -C "$PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_OK"* ]]
  [[ "$output" != *"not syncing the Claude credential"* ]]
}

@test "credential sync: --no-credential-sync is documented in --help" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-credential-sync"* ]]
}

@test "credential sync: refused behind a wrapper whose final binary cannot be checked" {
  require_runtime_sandbox
  run_scode -C "$PROJECT" -- env claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_OK"* ]]
  [[ "$output" == *"not syncing the Claude credential"* ]]
  [[ "$output" == *"is a wrapper"* ]]
  [ ! -e "$FAKE_HOME/.claude/.credentials.json" ]
}

@test "credential sync: refused for a claude binary inside the project" {
  require_runtime_sandbox
  mkdir -p "$PROJECT/bin"
  cp "$TOOLS/bin/claude" "$PROJECT/bin/claude"
  run_scode -C "$PROJECT" -- "$PROJECT/bin/claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_OK"* ]]
  [[ "$output" == *"lives inside the project"* ]]
  [ ! -e "$FAKE_HOME/.claude/.credentials.json" ]
}

@test "credential sync: refused when ~/.claude resolves into the project" {
  require_runtime_sandbox
  rm -rf "$FAKE_HOME/.claude"
  mkdir -p "$PROJECT/dotclaude"
  ln -s "$PROJECT/dotclaude" "$FAKE_HOME/.claude"
  run_scode -C "$PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_OK"* ]]
  [[ "$output" == *"is inside the project"* ]]
  [ ! -e "$PROJECT/dotclaude/.credentials.json" ]
}

@test "credential sync: a non-claude harness is left alone" {
  require_runtime_sandbox
  printf '#!/bin/bash\nprintf "CODEX_OK\\n"\n' > "$TOOLS/bin/codex"
  chmod +x "$TOOLS/bin/codex"
  run_scode -C "$PROJECT" -- codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"CODEX_OK"* ]]
  [[ "$output" != *"Claude credential"* ]]
}

@test "credential sync: a file-only login (no Keychain item) is left untouched and launches" {
  require_runtime_sandbox
  # `security` takes its keychain search list from $HOME (verified: with a
  # redirected HOME it exits 44, "not found", even on a machine whose real
  # login keychain holds the item). Skip rather than assert on a machine
  # where that does not hold.
  local probe_status=0
  HOME="$FAKE_HOME" security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 || probe_status=$?
  [ "$probe_status" -eq 44 ] || skip "a Keychain item is visible from the fake HOME on this machine"
  printf '{"claudeAiOauth":{"accessToken":"a","refreshToken":"only-copy"}}\n' > "$FAKE_HOME/.claude/.credentials.json"
  chmod 600 "$FAKE_HOME/.claude/.credentials.json"
  run_scode --no-credential-sync -C "$PROJECT" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_OK"* ]]
  grep -q only-copy "$FAKE_HOME/.claude/.credentials.json"
  run_scode -C "$PROJECT" -- env claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_OK"* ]]
  grep -q only-copy "$FAKE_HOME/.claude/.credentials.json"
}
