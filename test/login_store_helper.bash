#!/usr/bin/env bash
# Isolated synthetic login-store fixtures; never access the account's store.
setup() {
  TEST_PROJECT="$(mktemp -d)"
  _EXTRA_CLEANUP_DIRS=()
  unset SCODE_NET SCODE_FS_MODE
  export HOME="$TEST_PROJECT/home"
  export SCODE_CONFIG="$TEST_PROJECT/empty.yaml"
  export SECURITY_CALL_LOG="$TEST_PROJECT/security.calls"
  mkdir -p "$HOME/.claude" "$HOME/.gemini" "$HOME/project" "$TEST_PROJECT/bin" \
    "$HOME/Library/Keychains" "$HOME/Library/Preferences"
  export HOME="$(cd "$HOME" && pwd -P)"
  : > "$SCODE_CONFIG"
  : > "$SECURITY_CALL_LOG"
  : > "$HOME/Library/Preferences/com.apple.security.plist"
  cat > "$TEST_PROJECT/bin/security" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$SECURITY_CALL_LOG"
exit 99
SH
  local harness
  for harness in claude agy; do
    cp "$(type -P true)" "$TEST_PROJECT/bin/$harness"
  done
  chmod +x "$TEST_PROJECT/bin/"*
  export PATH="$TEST_PROJECT/bin:$PATH"
}

run_profile() {
  _SCODE_PLATFORM=darwin run "$SCODE" --dry-run -C "$HOME/project" "$@"
  [ "$status" -eq 0 ]
}

assert_access() {
  printf '%s\n' "$output" | node -e '
    const fs = require("node:fs");
    const assert = require("node:assert/strict");
    const { parseProfile, seatbelt } = require(process.argv[1]);
    const rules = parseProfile(fs.readFileSync(0, "utf8"));
    for (const op of ["read", "write"]) {
      assert.equal(seatbelt(rules, process.argv[2], op),
        process.argv[3] === "yes" || (process.argv[3] === "ro" && op === "read"),
        op + ": " + process.argv[2]);
    }
  ' "$BATS_TEST_DIRNAME/policy_evaluators.js" "$1" "$2"
}
