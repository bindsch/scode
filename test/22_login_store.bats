#!/usr/bin/env bats
load test_helper
load login_store_helper

@test "login-store: default denies both paths and explains sandbox access once" {
  require_node
  local harness mode line
  for harness in claude agy; do
    for mode in '' --strict; do
      run_profile $mode -- "$harness"
      assert_access "$HOME/Library/Keychains/fixture" no
      assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
      line="$(printf '%s\n' "$output" | grep 'no automatic login-store grant:')"
      [ "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" -eq 1 ]
      [[ "$line" == *"sandbox does not reach the macOS Keychain"*"Keychain login is not available inside it"* ]]
      [[ "$line" == *"--login-store"*"login_store: true"*"docs/security.md"* ]]
      [[ "$line" == *"$HOME/Library/Keychains read-write"*"$HOME/Library/Preferences/com.apple.security.plist read-only"* ]]
      [[ "$output" != *"logged out"* && "$output" != *"not logged in"* ]]
    done
  done
}

@test "login-store: only CLI or user config opts in and suppression always wins" {
  require_node
  local source mode harness
  for harness in claude agy; do
    for mode in '' --strict; do
      for source in user project false cli cli-first cli-last user-disabled project-disabled; do
        : > "$SCODE_CONFIG"
        : > "$HOME/project/.scode.yaml"
        local args=() expected=no
        case "$source" in
          user) printf 'login_store: true\n' > "$SCODE_CONFIG"; expected=yes ;;
          project) printf 'login_store: true\n' > "$HOME/project/.scode.yaml" ;;
          false) printf 'login_store: false\nno_login_store: false\n' > "$SCODE_CONFIG" ;;
          cli) printf 'login_store: false\n' > "$SCODE_CONFIG"; args=(--login-store); expected=yes ;;
          cli-first) args=(--login-store --no-login-store) ;;
          cli-last) args=(--no-login-store --login-store) ;;
          user-disabled) printf 'login_store: true\nno_login_store: true\n' > "$SCODE_CONFIG"; args=(--login-store) ;;
          project-disabled) printf 'login_store: true\n' > "$SCODE_CONFIG"
            printf 'no_login_store: true\n' > "$HOME/project/.scode.yaml" ;;
        esac
        run_profile $mode "${args[@]}" -- "$harness"
        assert_access "$HOME/Library/Keychains/fixture" "$expected"
        if [[ "$expected" == yes ]]; then
          assert_access "$HOME/Library/Preferences/com.apple.security.plist" ro
        else
          assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
        fi
      done
    done
  done
}

@test "login-store: invalid user and project opt-in values fail descriptively" {
  local config
  for config in "$SCODE_CONFIG" "$HOME/project/.scode.yaml"; do
    : > "$SCODE_CONFIG"
    : > "$HOME/project/.scode.yaml"
    printf 'login_store: maybe\n' > "$config"
    _SCODE_PLATFORM=darwin run "$SCODE" --dry-run -C "$HOME/project" -- claude
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid config: login_store: maybe"* ]]
  done
}

@test "login-store: references disclose opt-in, exact exposure, fallback, and staged path limits" {
  local doc text
  for doc in README.md docs/security.md docs/harnesses.md docs/policy.md docs/cli.md docs/configuration.md CHANGELOG.md examples/sandbox.yaml examples/sandbox-paranoid.yaml; do
    text="$(tr '\n' ' ' < "$BATS_TEST_DIRNAME/../$doc" | tr -d '#`' | tr -s ' ')"
    [[ "$text" == *"--login-store"* && "$text" == *"--no-login-store"* ]]
    [[ "$text" == *"login_store"* && "$text" == *"no_login_store"* ]]
    [[ "$text" == *"~/Library/Keychains"* && "$text" == *"~/Library/Preferences/com.apple.security.plist"* ]]
    [[ "$text" == *"/usr/bin/security"* && "$text" == *"without a dialog"* ]]
    [[ "$text" == *"refresh token"* && "$text" == *"login.keychain-db"* ]]
    [[ "$text" == *"login password"*"attacked offline"* ]]
    [[ "$text" == *"create, modify or delete files in the keychain directory"* ]]
    [[ "$text" == *"cannot change the default keychain or search list"*"read-only preference file"* ]]
    [[ "$text" == *".credentials.json"* && "$text" == *"does not inspect"* ]]
    [[ "$text" == *"--allow-staged"* && "$text" == *"whole staged path"* ]]
    [[ "$text" != *"credential copying remain"* && "$text" != *"automatic harness grants or copying"* ]]
    [[ "$text" != *"no stale refresh-token copy can exist"* ]]
  done
}

@test "login-store: non-executable and directory targets receive no grant" {
  require_node
  chmod -x "$TEST_PROJECT/bin/claude"
  run_profile --login-store -- "$TEST_PROJECT/bin/claude"
  assert_access "$HOME/Library/Keychains/fixture" no
  [[ "$output" == *"not a regular executable"* ]]
  mkdir -p "$TEST_PROJECT/other/claude"
  run_profile --login-store -- "$TEST_PROJECT/other/claude"
  assert_access "$HOME/Library/Keychains/fixture" no
  [[ "$output" == *"not a regular executable"* ]]
}

@test "login-store: interpreter entry scripts reached by name are declined" {
  require_node
  local harness mode layout
  for harness in claude agy; do
    for layout in direct symlink; do
      local bin="$TEST_PROJECT/$layout/bin"
      mkdir -p "$bin" "$TEST_PROJECT/$layout/package"
      printf '#!/usr/bin/env node\nthrow new Error("must never execute");\n' > "$TEST_PROJECT/$layout/package/cli.js"
      chmod +x "$TEST_PROJECT/$layout/package/cli.js"
      if [[ "$layout" == direct ]]; then
        cp "$TEST_PROJECT/$layout/package/cli.js" "$bin/$harness"
      else
        ln -s "$TEST_PROJECT/$layout/package/cli.js" "$bin/$harness"
      fi
      for mode in '' --strict; do
        PATH="$bin:$PATH" run_profile --login-store $mode -- "$harness"
        assert_access "$HOME/Library/Keychains/fixture" no
        assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
        [[ "$output" == *"no automatic login-store grant:"*"interpreter entry script"* ]]
        [[ "$output" != *"allowing login store:"* ]]
        [ "$(printf '%s\n' "$output" | grep -c 'no automatic login-store grant:')" -eq 1 ]
      done
    done
  done
}

@test "login-store: upgrade notes explain manual cleanup without login-state reporting" {
  local doc text
  for doc in CHANGELOG.md docs/security.md; do
    text="$(tr '\n' ' ' < "$BATS_TEST_DIRNAME/../$doc" | tr -d '`' | tr -s ' ')"
    [[ "$text" == *"0.6.7 scrubbed or refused"*"~/.claude/.credentials.json"*"refresh token"* ]]
    [[ "$text" == *"0.6.8 never inspects that file"* ]]
    [[ "$text" == *"older file login"*"confirming that your Keychain login works"*"remove the file yourself"* ]]
    [[ "$text" == *"scode prints nothing about login state"* ]]
  done
}

@test "login-store kernel: preference reads work but writes, replacements, and absent creation fail" {
  require_runtime_sandbox
  cat > "$HOME/project/check-preferences.sh" <<'SH'
#!/bin/sh
set -eu
pref="$HOME/Library/Preferences/com.apple.security.plist"
if [ "$1" = present ]; then
  test "$(/bin/cat "$pref")" = fixture
else
  if /bin/cat "$pref" >/dev/null 2>&1; then exit 10; fi
fi
if (printf denied > "$pref") 2>/dev/null; then echo 'unexpected preference write'; exit 11; fi
printf replacement > replacement
if /bin/mv -f replacement "$pref" 2>/dev/null; then echo 'unexpected preference replacement'; exit 12; fi
printf writable > "$HOME/Library/Keychains/fixture"
test "$(/bin/cat "$HOME/Library/Keychains/fixture")" = writable
printf 'PREFERENCE_READ_ONLY_OK\n'
SH
  ln -sf /bin/sh "$TEST_PROJECT/bin/claude"
  ln -sf /bin/sh "$TEST_PROJECT/bin/agy"
  local harness mode state pref="$HOME/Library/Preferences/com.apple.security.plist"
  for harness in claude agy; do
    for mode in '' --strict; do
      printf fixture > "$pref"
      for state in present absent; do
        if [[ "$state" == absent ]]; then mv "$pref" "$TEST_PROJECT/preferences.saved"; fi
        run "$SCODE" --login-store $mode -C "$HOME/project" -- "$TEST_PROJECT/bin/$harness" "$HOME/project/check-preferences.sh" "$state"
        echo "$output"
        [ "$status" -eq 0 ]
        [[ "$output" == *"PREFERENCE_READ_ONLY_OK"* ]]
        if [[ "$state" == present ]]; then [ "$(cat "$pref")" = fixture ]
        else [ ! -e "$pref" ]; fi
        [ ! -s "$SECURITY_CALL_LOG" ]
      done
    done
  done
}
