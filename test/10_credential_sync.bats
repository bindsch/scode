#!/usr/bin/env bats
# Offline gate: fake harnesses and a PATH spy, backed by static parent checks.
load test_helper
load login_store_helper

@test "no-keychain: launcher has no credential commands or synchronization" {
  # The parent pins PATH; the child spy cannot intercept its system calls.
  # Help must describe security's exposure; scan executable code separately.
  no_credential_commands() {
    sed '/^usage() {/,/^}/d' "$SCODE_SOURCE" |
      grep -En 'find-generic-password|add-generic-password|delete-generic-password|find-internet-password|add-internet-password|default-keychain|unlock-keychain|lock-keychain|list-keychains|create-keychain|delete-keychain|dump-keychain|set-keychain|security[[:space:]]+[-[:alnum:]]|/usr/bin/security|\.credentials\.json|credential-backups|CREDENTIAL_SYNC|sync_claude_credential|refuse_claude_refresh'
  }
  run no_credential_commands
  [ "$status" -eq 1 ]
}

@test "no-keychain: legacy flag is documented as a no-op" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-credential-sync"* ]]
  [[ "$output" == *"Compatibility no-op for 0.6.8"* ]]
}

@test "no-keychain: fake harnesses run in every mode without calls or state writes" {
  require_any_runtime_sandbox
  local harness mode
  for harness in claude agy; do
    for mode in normal strict legacy untrusted; do
      local args=()
      case "$mode" in
        strict) args=(--strict) ;;
        legacy) args=(--no-credential-sync) ;;
        untrusted) args=(--trust untrusted) ;;
      esac
      # Keep the spy executable and its log writable even in untrusted mode.
      run "$SCODE" "${args[@]}" --allow "$TEST_PROJECT/bin" --allow "$SECURITY_CALL_LOG" \
        -C "$HOME/project" -- "$TEST_PROJECT/bin/$harness"
      [ "$status" -eq 0 ]
      [ ! -s "$SECURITY_CALL_LOG" ]
      [ -z "$(find "$HOME/.claude" "$HOME/.gemini" -mindepth 1 -print)" ]
      [ ! -e "$HOME/Library/Application Support/scode" ]
    done
  done
}

@test "no-keychain: existing mirror and backups remain unchanged and never refuse launch" {
  require_any_runtime_sandbox
  local backup_dir="$HOME/Library/Application Support/scode/credential-backups"
  mkdir -p "$backup_dir"
  printf '{"claudeAiOauth":{"refreshToken":"synthetic-only"}}\n' > "$HOME/.claude/.credentials.json"
  cp "$HOME/.claude/.credentials.json" "$TEST_PROJECT/original"
  cp "$TEST_PROJECT/original" "$backup_dir/credentials.fixture"
  local mode
  for mode in '' --strict --no-credential-sync; do
    run "$SCODE" $mode --allow "$TEST_PROJECT/bin" --allow "$SECURITY_CALL_LOG" \
      -C "$HOME/project" -- "$TEST_PROJECT/bin/claude"
    [ "$status" -eq 0 ]
    cmp "$TEST_PROJECT/original" "$HOME/.claude/.credentials.json"
    cmp "$TEST_PROJECT/original" "$backup_dir/credentials.fixture"
    [ "$(find "$HOME/.claude" "$backup_dir" -type f | wc -l | tr -d ' ')" -eq 2 ]
    [ ! -s "$SECURITY_CALL_LOG" ]
  done
}

@test "no-keychain: macOS grants only login paths for claude and agy" {
  require_node
  local harness mode
  for harness in claude agy; do
    for mode in '' --strict --no-credential-sync; do
      run_profile --login-store $mode -- "$harness"
      assert_access "$HOME/Library/Keychains/login.keychain-db" yes
      assert_access "$HOME/Library/Preferences/com.apple.security.plist" ro
      assert_access "$HOME/Library/Preferences/unrelated.plist" no
      assert_access "$HOME/Library/Application Support/browser/data" no
      if [[ "$mode" == --strict ]]; then
        local info_line
        info_line="$(printf '%s\n' "$output" | grep "$harness: allowing login store:")"
        [[ "$info_line" == *"$HOME/Library/Keychains"* ]]
        [[ "$info_line" == *"$HOME/Library/Preferences/com.apple.security.plist"* ]]
        [[ "$output" == *"(allow mach-lookup)"* ]]
        # The blanket allow is narrowed only when the grant is not applied.
        [[ "$output" != *"(deny mach-lookup"* ]]
        run_profile --strict -- "$harness"
        [[ "$output" == *"(allow mach-lookup)"*"(deny mach-lookup"*"(global-name \"com.apple.authd\")"* ]]
        [[ "$output" == *"(allow process-exec)"* ]]
        [[ "$output" == *'(subpath "/usr")'* ]]
      else
        [[ "$output" == *"(allow default)"* ]]
      fi
    done
  done
}

@test "no-keychain: kernel enforces login grants and denies unrelated Library data and metadata" {
  require_runtime_sandbox
  # Every read below targets synthetic files in this test's isolated HOME.
  printf 'fixture\n' > "$HOME/Library/Keychains/fixture.txt"
  printf 'fixture\n' > "$HOME/Library/Preferences/com.apple.security.plist"
  printf 'fixture\n' > "$HOME/Library/Preferences/unrelated.plist"
  mkdir -p "$HOME/Library/Application Support/browser"
  printf 'fixture\n' > "$HOME/Library/Application Support/browser/data"
  cat > "$TEST_PROJECT/bin/check-library.sh" <<'SH'
#!/bin/sh
set -eu
expect_read() {
  if /bin/cat "$1" >/dev/null 2>&1; then actual=yes; else actual=no; fi
  if [ "$actual" != "$2" ]; then
    printf 'read %s: expected %s, got %s\n' "$1" "$2" "$actual"
    exit 1
  fi
}
expect_read "$HOME/Library/Keychains/fixture.txt" "$1"
expect_read "$HOME/Library/Preferences/com.apple.security.plist" "$2"
expect_read "$HOME/Library/Preferences/unrelated.plist" no
expect_read "$HOME/Library/Application Support/browser/data" no
if [ "$3" = strict ]; then
  for path in "$HOME/Library/Preferences/unrelated.plist" "$HOME/Library/Application Support/browser/data"; do
    if /usr/bin/stat -f '%z' "$path" >/dev/null 2>&1; then
      printf 'unexpected metadata access: %s\n' "$path"
      exit 1
    fi
  done
fi
printf 'KERNEL_LIBRARY_BOUNDARY_OK\n'
SH
  # A native shell fixture runs the permission probe without a real harness.
  ln -sf /bin/sh "$TEST_PROJECT/bin/claude"
  ln -sf /bin/sh "$TEST_PROJECT/bin/agy"
  local harness mode
  for harness in claude agy; do
    for mode in normal strict legacy untrusted blocked disabled default; do
      local args=() keychains=yes preferences=yes metadata=normal
      case "$mode" in
        strict) args=(--strict); metadata=strict ;;
        legacy) args=(--no-credential-sync) ;;
        untrusted) args=(--trust untrusted); keychains=no; preferences=no; metadata=strict ;;
        blocked) args=(--strict --block "$HOME/Library"); keychains=no; preferences=no; metadata=strict ;;
        disabled) args=(--no-login-store); keychains=no; preferences=no ;;
        default) keychains=no; preferences=no ;;
      esac
      [[ "$mode" == default ]] || args+=(--login-store)
      run "$SCODE" "${args[@]}" --allow "$TEST_PROJECT/bin" -C "$HOME/project" \
        -- "$TEST_PROJECT/bin/$harness" "$TEST_PROJECT/bin/check-library.sh" "$keychains" "$preferences" "$metadata"
      [ "$status" -eq 0 ]
      [[ "$output" == *"KERNEL_LIBRARY_BOUNDARY_OK"* ]]
      [ ! -s "$SECURITY_CALL_LOG" ]
    done
  done
}

@test "no-keychain: untrusted and other harnesses receive no login-store grant" {
  require_node
  local harness mode
  for harness in claude agy; do
    run_profile --login-store --trust untrusted -- "$harness"
    assert_access "$HOME/Library/Keychains/login.keychain-db" no
    assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
  done
  for harness in codex gemini cursor-agent /usr/bin/true; do
    for mode in '' --strict; do
      run_profile --login-store $mode -- "$harness"
      assert_access "$HOME/Library/Keychains/login.keychain-db" no
      assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
    done
  done
}

@test "no-keychain: absent preferences are not granted or created" {
  require_node
  mv "$HOME/Library/Preferences/com.apple.security.plist" "$TEST_PROJECT/preferences.fixture"
  run_profile --login-store --strict -- claude
  assert_access "$HOME/Library/Keychains/login.keychain-db" yes
  assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
  [ ! -e "$HOME/Library/Preferences/com.apple.security.plist" ]
}

@test "no-keychain: a directory or link at the preference path is never granted" {
  require_node
  local kind
  for kind in directory link; do
    rm -rf "$HOME/Library/Preferences/com.apple.security.plist"
    if [[ "$kind" == directory ]]; then
      mkdir -p "$HOME/Library/Preferences/com.apple.security.plist"
      printf secret > "$HOME/Library/Preferences/com.apple.security.plist/inner"
    else
      printf secret > "$HOME/Library/Preferences/elsewhere.plist"
      ln -s "$HOME/Library/Preferences/elsewhere.plist" "$HOME/Library/Preferences/com.apple.security.plist"
    fi
    run_profile --login-store --strict -- claude
    # A directory there is simply not granted; a link declines the whole
    # login-store grant as a redirected store.
    if [[ "$kind" == directory ]]; then
      assert_access "$HOME/Library/Keychains/login.keychain-db" yes
    else
      assert_access "$HOME/Library/Keychains/login.keychain-db" no
    fi
    assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
    assert_access "$HOME/Library/Preferences/com.apple.security.plist/inner" no
    assert_access "$HOME/Library/Preferences/elsewhere.plist" no
  done
}

@test "no-keychain: CLI, user, and project blocks suppress overlapping grants" {
  require_node
  local mode source blocked
  for mode in '' --strict; do
    for source in cli user project; do
      for blocked in "$HOME/Library" "$HOME/Library/Keychains" "$HOME/Library/Keychains/child" "$HOME/Library/Preferences/com.apple.security.plist"; do
        : > "$SCODE_CONFIG"
        : > "$HOME/project/.scode.yaml"
        local args=()
        case "$source" in
          cli) args=(--block "$blocked") ;;
          user) printf 'blocked:\n  - %s\n' "$blocked" > "$SCODE_CONFIG" ;;
          project) printf 'blocked:\n  - %s\n' "$blocked" > "$HOME/project/.scode.yaml" ;;
        esac
        run_profile --login-store $mode "${args[@]}" -- claude
        assert_access "$HOME/Library/Keychains/login.keychain-db" no
        assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
      done
    done
    : > "$SCODE_CONFIG"
    : > "$HOME/project/.scode.yaml"
    run_profile --login-store $mode --block "$HOME/Library/Preferences/com.apple.security.plist" -- agy
    assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
    assert_access "$HOME/Library/Keychains/login.keychain-db" no
  done
}

@test "no-keychain: redirected login stores never open another Library subtree" {
  require_node
  mv "$HOME/Library/Keychains" "$HOME/Library/other"
  ln -s "$HOME/Library/other" "$HOME/Library/Keychains"
  run_profile --login-store --strict -- agy
  assert_access "$HOME/Library/other/data" no
  # No allow names the directory; it appears only in the final deny.
  local granted="${output%%"(deny mach-lookup"*}"
  [[ "$granted" != *"(subpath \"$HOME/Library/Keychains\")"* ]]
  [[ "$output" == *"(deny mach-lookup"*"(deny file-read* file-write*"*"(subpath \"$HOME/Library/Keychains\")"* ]]
}

@test "no-keychain: Linux has no macOS login grants" {
  local harness
  for harness in claude agy; do
    _SCODE_PLATFORM=linux run "$SCODE" --dry-run --login-store --strict -C "$HOME/project" -- "$harness"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Library/Keychains"* ]]
    [[ "$output" != *"com.apple.security.plist"* ]]
  done
}

@test "login-store: project launchers, symlink targets, entry scripts, and wrappers are declined" {
  require_node
  local harness command mode
  mkdir -p "$HOME/project/node_modules/.bin" "$HOME/project/node_modules/@anthropic-ai/claude-code"
  cp "$TEST_PROJECT/bin/claude" "$HOME/project/node_modules/@anthropic-ai/claude-code/cli.js"
  for harness in claude agy; do
    cp "$TEST_PROJECT/bin/$harness" "$HOME/project/$harness"
    cp "$TEST_PROJECT/bin/$harness" "$HOME/project/node_modules/.bin/$harness"
    mkdir -p "$TEST_PROJECT/links"
    ln -s "$HOME/project/$harness" "$TEST_PROJECT/links/$harness"
    for mode in '' --strict; do
      for command in "./$harness" "node_modules/.bin/$harness" "$TEST_PROJECT/links/$harness"; do
        run_profile --login-store $mode -- "$command"
        assert_access "$HOME/Library/Keychains/login.keychain-db" no
        [[ "$output" == *"resolved harness executable is inside the project"* ]]
        [[ "$output" == *"$HOME/Library/Keychains read-write"*"$HOME/Library/Preferences/com.apple.security.plist read-only"* ]]
      done
      PATH="$HOME/project:$PATH" run_profile --login-store $mode -- "$harness"
      assert_access "$HOME/Library/Keychains/login.keychain-db" no
      run_profile --login-store $mode -- /bin/sh -c "true; $harness"
      assert_access "$HOME/Library/Keychains/login.keychain-db" no
      [[ "$output" == *"entry scripts and wrappers are ineligible"* ]]
      run_profile --login-store $mode -- /usr/bin/env "PATH=$HOME/project:$PATH" "$harness"
      assert_access "$HOME/Library/Keychains/login.keychain-db" no
      [[ "$output" == *"entry scripts and wrappers are ineligible"* ]]
    done
  done
  run_profile --login-store -- "$HOME/project/node_modules/@anthropic-ai/claude-code/cli.js"
  assert_access "$HOME/Library/Keychains/login.keychain-db" no
  [[ "$output" == *"entry scripts and wrappers are ineligible"* ]]
  run_profile --login-store -- node "$HOME/project/node_modules/@anthropic-ai/claude-code/cli.js"
  assert_access "$HOME/Library/Keychains/login.keychain-db" no
  assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
  # Interpreters are not detected as harnesses, so there is no grant message.
  [[ "$output" != *": allowing login store:"* ]]
  # An unrecognized wrapper is not a detected harness and gains no login access.
  cp "$TEST_PROJECT/bin/claude" "$TEST_PROJECT/bin/custom-wrapper"
  run_profile --login-store -- custom-wrapper claude
  assert_access "$HOME/Library/Keychains/login.keychain-db" no
}

assert_native_install_grant() {
  require_node
  local harness target bin mode command
  for harness in claude agy; do
    if [[ "$1" == native ]]; then
      target="$HOME/.local/share/$harness/versions/2.0.99"
      bin="$HOME/.local/bin"
    else
      target="$HOME/homebrew/Caskroom/$harness/2.0.99/bin/$harness.exe"
      bin="$HOME/homebrew/bin"
    fi
    mkdir -p "${target%/*}" "$bin"
    cp "$(type -P true)" "$target"
    ln -s "$target" "$bin/$harness"
    for mode in '' --strict; do
      for command in "$harness" "$bin/$harness"; do
        PATH="$bin:$PATH" run_profile --login-store $mode -- "$command"
        assert_access "$HOME/Library/Keychains/login.keychain-db" yes
        assert_access "$HOME/Library/Preferences/com.apple.security.plist" ro
        [[ "$output" == *"$harness: allowing login store:"* ]]
      done
    done
  done
  ln -s "$target" "$TEST_PROJECT/bin/alias"
  run_profile --login-store -- "$TEST_PROJECT/bin/alias"
  assert_access "$HOME/Library/Keychains/login.keychain-db" no
}

@test "login-store: native binaries through version-number install symlinks qualify" {
  assert_native_install_grant native
}

@test "login-store: native binaries through Homebrew exe symlinks qualify" {
  assert_native_install_grant homebrew
}

@test "login-store: CLI and config opt-outs suppress both grants without revoking explicit authority" {
  require_node
  local mode harness source
  for harness in claude agy; do
    for mode in '' --strict; do
      for source in cli user project; do
        : > "$SCODE_CONFIG"
        : > "$HOME/project/.scode.yaml"
        local args=()
        case "$source" in
          cli) args=(--no-login-store); printf 'no_login_store: false\n' > "$SCODE_CONFIG" ;;
          user) printf 'no_login_store: true\n' > "$SCODE_CONFIG"
                printf 'no_login_store: false\n' > "$HOME/project/.scode.yaml" ;;
          project) printf 'no_login_store: true\n' > "$HOME/project/.scode.yaml" ;;
        esac
        run_profile --login-store $mode "${args[@]}" -- "$harness"
        assert_access "$HOME/Library/Keychains/login.keychain-db" no
        assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
        [[ "$output" == *"no automatic login-store grant:"*"no_login_store: true is set"* ]]
      done
    done
  done
  : > "$HOME/project/.scode.yaml"
  printf 'no_login_store: false\n' > "$SCODE_CONFIG"
  run_profile --login-store -- claude
  assert_access "$HOME/Library/Keychains/login.keychain-db" yes
  # Without the grant the final rule closes the directory, whatever is allowed.
  run_profile --no-login-store --allow "$HOME/Library/Keychains" -- claude
  assert_access "$HOME/Library/Keychains/login.keychain-db" no
  printf 'no_login_store: maybe\n' > "$SCODE_CONFIG"
  run "$SCODE" --dry-run -C "$HOME/project" -- claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid config: no_login_store: maybe"* ]]
}

@test "login-store: normal and strict grants are visible and logged" {
  require_runtime_sandbox
  local mode line log="$HOME/project/login.log"
  for mode in '' --strict; do
    run "$SCODE" --login-store $mode --log "$log" --allow "$TEST_PROJECT/bin" -C "$HOME/project" -- claude
    [ "$status" -eq 0 ]
    line="$(printf '%s\n' "$output" | grep 'claude: allowing login store:')"
    [[ "$line" == *"$HOME/Library/Keychains"*"$HOME/Library/Preferences/com.apple.security.plist"* ]]
    [ "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" -eq 1 ]
    run grep -Fx "# allowed: $HOME/Library/Keychains" "$log"
    [ "$status" -eq 0 ]
    run grep -Fx "# allowed_ro: $HOME/Library/Preferences/com.apple.security.plist" "$log"
    [ "$status" -eq 0 ]
  done
}

@test "login-store: trailing slash and symlink HOME retain canonical grants" {
  require_node
  local canonical_home="$HOME" home_spelling harness
  ln -s "$HOME" "$TEST_PROJECT/home-link"
  for home_spelling in "$canonical_home/" "$TEST_PROJECT/home-link"; do
    for harness in claude agy; do
      HOME="$home_spelling" run_profile --login-store -- "$harness"
      assert_access "$canonical_home/Library/Keychains/login.keychain-db" yes
      assert_access "$canonical_home/Library/Preferences/com.apple.security.plist" ro
      [[ "$output" == *"allowing login store: $canonical_home/Library/Keychains"* ]]
    done
  done
}

@test "login-store: help and security docs disclose exposure, controls, and single-store design" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  local help="$output" doc text
  for doc in help README.md docs/security.md docs/harnesses.md; do
    if [[ "$doc" == help ]]; then text="$help"; else text="$(cat "$BATS_TEST_DIRNAME/../$doc")"; fi
    text="$(printf '%s\n' "$text" | tr '\n' ' ' | tr -s ' ')"
    [[ "$text" == *"/usr/bin/security"*"without a dialog"* ]]
    [[ "$text" == *"refresh"*"token"*"GitHub CLI token"* ]]
    [[ "$text" == *"create, modify or delete files in the keychain"* ]]
    [[ "$text" == *"login.keychain-db"*"login password"*"attacked offline"* ]]
    [[ "$text" == *"cannot change the default keychain or search list"*"read-only preference file"* ]]
    [[ "$text" == *"off by default"*"--login-store"*"login_store: true"* ]]
    [[ "$text" == *"preference file"* ]]
    [[ "$text" == *"--no-login-store"*"--block"*"--trust untrusted"* ]]
    [[ "$text" == *"cannot use a Keychain login"* ]]
    [[ "$text" == *"one login store"*"stale"*"refresh-token copy"* ]]
    [[ "$text" == *".credentials.json"*"does not inspect that file"* ]]
    [[ "$text" != *"no stale refresh-token copy can exist"* ]]
    [[ "$text" != *"unrelated items subject to macOS controls"* ]]
  done
}
