#!/usr/bin/env bats
# Keychain service reach on macOS. One decision in the launcher yields both the
# login-store file grant and the Mach rule for the keychain daemons.
#
# Every check here is passive: profile text, and bootstrap lookups that only
# ask launchd whether a name may be looked up. No test stores to or reads from
# a keychain, runs a Keychain tool, or sends a message to a security daemon.
load test_helper
load login_store_helper

KEYCHAIN_SERVICE_NAMES=(
  com.apple.SecurityServer
  com.apple.securityd.xpc
  com.apple.authd
  com.apple.security.agent
  com.apple.security.agent.login
  com.apple.security.authhost
)

# The profile is everything a dry-run prints before its "# Command:" trailer.
profile_text() {
  printf '%s\n' "$output" | sed '/^# Command:/,$d'
}

# assert_keychain_services denied|reachable
assert_keychain_services() {
  local profile name tail
  profile="$(profile_text)"
  # No filtered Mach allow may exist anywhere: it is the only rule form that
  # could reopen a denied name.
  if printf '%s\n' "$profile" | grep -E '\(allow[^)]*mach-lookup[^)]*\((global-name|local-name|xpc-service-name)'; then
    echo "filtered Mach allow present"
    return 1
  fi
  if [[ "$1" == reachable ]]; then
    if [[ "$profile" == *"(deny mach-lookup"* ]]; then
      echo "unexpected keychain service deny"
      return 1
    fi
    return 0
  fi
  if [ "$(printf '%s\n' "$profile" | grep -c '^(deny mach-lookup$')" -ne 1 ]; then
    echo "expected exactly one keychain service deny"
    printf '%s\n' "$profile" | tail -n 20
    return 1
  fi
  tail="${profile##*"(deny mach-lookup"}"
  for name in "${KEYCHAIN_SERVICE_NAMES[@]}"; do
    if [[ "$tail" != *"(global-name \"$name\")"* ]]; then
      echo "deny does not name $name"
      return 1
    fi
  done
  # The deny is the last rule: no allow of any kind follows it.
  if [[ "$tail" == *"(allow"* ]]; then
    echo "an allow rule follows the keychain service deny"
    return 1
  fi
}

@test "keychain services: denied for every command without the login-store grant" {
  local mode cmd
  for cmd in true claude agy; do
    for mode in '' --strict --ro '--trust untrusted' '--trust trusted' --no-net \
        --no-login-store '--strict --no-login-store' '--login-store --no-login-store'; do
      # shellcheck disable=SC2086
      run_profile $mode -- "$cmd"
      assert_keychain_services denied
    done
  done
}

@test "keychain services: reachable only with an applied grant and a resolvable login keychain" {
  require_node
  local harness mode
  for harness in claude agy; do
    for mode in '' --strict --ro '--strict --ro --no-net'; do
      # shellcheck disable=SC2086
      run_profile --login-store $mode -- "$harness"
      assert_keychain_services reachable
      assert_access "$HOME/Library/Keychains/login.keychain-db" yes
      [[ "$output" == *"$harness: allowing login store:"* ]]
    done
  done
  printf 'login_store: true\n' > "$SCODE_CONFIG"
  run_profile -- claude
  assert_keychain_services reachable
  assert_access "$HOME/Library/Keychains/login.keychain-db" yes
}

@test "keychain services: every cancellation of the grant restores the deny" {
  require_node
  local mode
  # Opt-out, untrusted preset, and overlapping blocks.
  for mode in --no-login-store '--trust untrusted' '--strict --trust untrusted' \
      "--block $HOME/Library" "--block $HOME/Library/Keychains" \
      "--block $HOME/Library/Preferences/com.apple.security.plist" \
      "--strict --block $HOME/Library/Keychains"; do
    # shellcheck disable=SC2086
    run_profile --login-store $mode -- claude
    assert_keychain_services denied
    assert_access "$HOME/Library/Keychains/login.keychain-db" no
  done
  # User and project opt-outs and blocks.
  printf 'no_login_store: true\n' > "$SCODE_CONFIG"
  run_profile --login-store -- claude
  assert_keychain_services denied
  : > "$SCODE_CONFIG"
  printf 'no_login_store: true\n' > "$HOME/project/.scode.yaml"
  run_profile --login-store -- agy
  assert_keychain_services denied
  printf 'blocked:\n  - %s\n' "$HOME/Library/Keychains" > "$HOME/project/.scode.yaml"
  run_profile --login-store --strict -- claude
  assert_keychain_services denied
  # Project config cannot opt in.
  printf 'login_store: true\n' > "$HOME/project/.scode.yaml"
  run_profile -- claude
  assert_keychain_services denied
}

@test "keychain services: ineligible launches stay denied after opt-in" {
  require_node
  local mode
  for mode in '' --strict; do
    # Not a login-store harness.
    run_profile --login-store $mode -- true
    assert_keychain_services denied
    # A wrapper names another program.
    run_profile --login-store $mode -- /bin/sh -c claude
    assert_keychain_services denied
    # An interpreter entry script.
    mkdir -p "$TEST_PROJECT/script-bin"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_PROJECT/script-bin/claude"
    chmod +x "$TEST_PROJECT/script-bin/claude"
    PATH="$TEST_PROJECT/script-bin:$PATH" run_profile --login-store $mode -- claude
    assert_keychain_services denied
    [[ "$output" == *"interpreter entry script"* ]]
    # A harness executable inside the project.
    cp "$TEST_PROJECT/bin/claude" "$HOME/project/claude"
    run_profile --login-store $mode -- "$HOME/project/claude"
    assert_keychain_services denied
    rm -f "$HOME/project/claude"
  done
}

@test "keychain services: an explicit allow of the Keychains directory does not reopen them" {
  require_node
  local mode cmd extra
  for cmd in true claude; do
    for mode in '' --strict --no-login-store '--trust untrusted'; do
      for extra in "$HOME/Library/Keychains" "$HOME/Library"; do
        # shellcheck disable=SC2086
        run_profile $mode --allow "$extra" -- "$cmd"
        assert_keychain_services denied
        # The file rule still has its documented authority.
        assert_access "$HOME/Library/Keychains/login.keychain-db" yes
      done
    done
  done
  printf 'allowed:\n  - %s\n' "$HOME/Library/Keychains" > "$SCODE_CONFIG"
  run_profile -- claude
  assert_keychain_services denied
  run_profile --allow-ro "$HOME/Library/Preferences/com.apple.security.plist" \
    --allow "$HOME/Library/Keychains" -- true
  assert_keychain_services denied
}

@test "keychain services: a granted launch with no resolvable login keychain is denied" {
  require_node
  local db="$HOME/Library/Keychains/login.keychain-db" mode state
  for mode in '' --strict; do
    for state in absent dangling outside directory; do
      rm -rf "$db"
      case "$state" in
        dangling) ln -s "$HOME/Library/Keychains/missing" "$db" ;;
        outside)
          : > "$HOME/project/elsewhere.keychain-db"
          ln -s "$HOME/project/elsewhere.keychain-db" "$db" ;;
        directory) mkdir "$db" ;;
      esac
      run_profile --login-store $mode -- claude
      assert_keychain_services denied
      # Files and services cannot diverge: no login keychain, no file grant.
      assert_access "$HOME/Library/Keychains/fixture" no
      assert_access "$HOME/Library/Preferences/com.apple.security.plist" no
      [[ "$output" == *"no automatic login-store grant: no login keychain resolves at $db"* ]]
      [[ "$output" != *"allowing login store:"* ]]
    done
    # A link that stays inside the directory still resolves.
    rm -rf "$db"
    : > "$HOME/Library/Keychains/real.keychain-db"
    ln -s "$HOME/Library/Keychains/real.keychain-db" "$db"
    run_profile --login-store $mode -- claude
    assert_keychain_services reachable
    rm -rf "$db"
    : > "$db"
  done
}

@test "keychain services: a recorded default keychain must exist inside the granted directory" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  require_node
  local prefs="$HOME/Library/Preferences/com.apple.security.plist"
  mkdir -p "$HOME/Library/Preferences" "$TEST_PROJECT/elsewhere"
  : > "$TEST_PROJECT/elsewhere/work.keychain-db"
  # The shape macOS writes: an array whose element zero names the keychain.
  write_prefs() {
    rm -f "$prefs"
    /usr/bin/plutil -create xml1 "$prefs"
    /usr/bin/plutil -insert DefaultKeychain -array "$prefs"
    /usr/bin/plutil -insert DefaultKeychain.0 -dictionary "$prefs"
    /usr/bin/plutil -insert DefaultKeychain.0.DbName -string "$1" "$prefs"
  }
  write_prefs "$TEST_PROJECT/elsewhere/work.keychain-db"
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"the recorded default keychain is outside"* ]]
  write_prefs "$HOME/Library/Keychains/gone.keychain-db"
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"the recorded default keychain does not exist"* ]]
  local name
  for name in "~/Library/Keychains/login.keychain-db" "~/Library/Keychains/login.keychain" \
      "$HOME/Library/Keychains/login.keychain-db"; do
    write_prefs "$name"
    run_profile --login-store -- claude
    assert_keychain_services reachable
  done
  # An array with no usable first element means no default keychain at all.
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DefaultKeychain -array "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"records no default keychain"* ]]
  /usr/bin/plutil -insert DefaultKeychain.0 -string "$HOME/Library/Keychains/login.keychain-db" "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services denied
  # Security.framework ignores a file it cannot parse and a value of another
  # shape, and uses the login keychain; neither declines the grant.
  printf 'not a plist' > "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services reachable
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DefaultKeychain -dictionary "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.DbName -string "/nonexistent/x.keychain-db" "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services reachable
  /usr/bin/plutil -remove DefaultKeychain.DbName "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.0.DbName -string "/nonexistent/x.keychain-db" "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services reachable
}

@test "keychain services: a recorded login keychain must exist inside the granted directory" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  require_node
  # Measured: with no usable DefaultKeychain record, a LoginKeychain record
  # naming a missing file leaves the account without a default keychain,
  # although login.keychain-db exists.
  local prefs="$HOME/Library/Preferences/com.apple.security.plist"
  mkdir -p "$HOME/Library/Preferences" "$TEST_PROJECT/elsewhere"
  : > "$TEST_PROJECT/elsewhere/work.keychain-db"
  write_login_prefs() {
    rm -f "$prefs"
    /usr/bin/plutil -create xml1 "$prefs"
    /usr/bin/plutil -insert LoginKeychain -array "$prefs"
    /usr/bin/plutil -insert LoginKeychain.0 -dictionary "$prefs"
    /usr/bin/plutil -insert LoginKeychain.0.DbName -string "$1" "$prefs"
  }
  write_login_prefs "$HOME/Library/Keychains/gone.keychain-db"
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"the recorded login keychain does not exist"* ]]
  write_login_prefs "$TEST_PROJECT/elsewhere/work.keychain-db"
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"the recorded login keychain is outside"* ]]
  write_login_prefs "~/Library/Keychains/login.keychain-db"
  run_profile --login-store -- claude
  assert_keychain_services reachable
  # A valid default record does not excuse a broken login record.
  write_login_prefs "$HOME/Library/Keychains/gone.keychain-db"
  /usr/bin/plutil -insert DefaultKeychain -array "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.0.DbName -string "~/Library/Keychains/login.keychain-db" "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services denied
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert LoginKeychain -array "$prefs"
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"records no login keychain"* ]]
  # A recorded name with a trailing newline names a different, missing
  # file; it must not be validated as the newline-free one.
  write_login_prefs "$HOME/Library/Keychains/login.keychain-db"$'\n'
  run_profile --login-store -- claude
  assert_keychain_services denied
  [[ "$output" == *"records no login keychain"* ]]
  write_login_prefs "$HOME/Library/Keychains/login.keychain-db"$'\t'
  run_profile --login-store -- claude
  assert_keychain_services denied
  # A relative name resolves differently in the child, which starts in
  # the project directory.
  (cd "$HOME/Library/Keychains" && write_login_prefs "login.keychain-db" &&
    run_profile --login-store -- claude && assert_keychain_services denied &&
    [[ "$output" == *"is not an absolute path"* ]])
}

@test "keychain services: an unreadable preference file declines the grant, even an empty one" {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"
  [[ "$(id -u)" -ne 0 ]] || skip "root reads any file"
  require_node
  local prefs="$HOME/Library/Preferences/com.apple.security.plist"
  mkdir -p "$HOME/Library/Preferences"
  rm -f "$prefs"; : > "$prefs"; chmod 000 "$prefs"
  run_profile --login-store -- claude
  chmod 600 "$prefs"
  assert_keychain_services denied
  [[ "$output" == *"the preference file cannot be checked"* ]]
}

@test "keychain services: a private HOME without a login store is denied even after opt-in" {
  require_node
  local private mode optin
  private="$TEST_PROJECT/private-home"
  mkdir -p "$private/project"
  private="$(cd "$private" && pwd -P)"
  for mode in '' --strict '--trust untrusted'; do
    for optin in '' --login-store; do
      # shellcheck disable=SC2086
      HOME="$private" _SCODE_PLATFORM=darwin run "$SCODE" --dry-run $optin $mode \
        -C "$private/project" -- claude
      [ "$status" -eq 0 ]
      assert_keychain_services denied
      assert_access "$private/Library/Keychains/login.keychain-db" no
      [[ "$output" != *"allowing login store:"* ]]
    done
  done
  # An empty Keychains directory in the private HOME changes nothing.
  mkdir -p "$private/Library/Keychains"
  HOME="$private" _SCODE_PLATFORM=darwin run "$SCODE" --dry-run --login-store \
    -C "$private/project" -- claude
  [ "$status" -eq 0 ]
  assert_keychain_services denied
}

@test "keychain services: Linux emits no Mach rule" {
  _SCODE_PLATFORM=linux run "$SCODE" --dry-run --login-store --strict -C "$HOME/project" -- claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"mach-lookup"* ]]
  [[ "$output" != *"com.apple."* ]]
}

@test "keychain services: help and docs state the rule" {
  run "$SCODE" --help
  [ "$status" -eq 0 ]
  local help="$output" doc text
  for doc in help README.md docs/security.md docs/policy.md docs/cli.md docs/harnesses.md CHANGELOG.md; do
    if [[ "$doc" == help ]]; then text="$help"; else text="$(cat "$BATS_TEST_DIRNAME/../$doc")"; fi
    text="$(printf '%s\n' "$text" | tr '\n' ' ' | tr -d '`' | tr -s ' ')"
    [[ "$text" == *"com.apple.SecurityServer"*"com.apple.authd"* ]]
    [[ "$text" == *"login.keychain-db"* ]]
  done
  text="$(tr '\n' ' ' < "$BATS_TEST_DIRNAME/../docs/security.md" | tr -d '`' | tr -s ' ')"
  [[ "$text" == *"com.apple.security.agent"*"com.apple.security.authhost"* ]]
  [[ "$text" == *"com.apple.securityd.xpc"* ]]
  [[ "$text" != *"com.apple.securityd.xpc) also stays reachable"* ]]
  [[ "$text" == *"does not make the services reachable"* ]]
  [[ "$text" != *"securityd reachable for that purpose"* ]]
}

# ---------- Kernel: passive bootstrap lookups ----------

# Build a probe that asks launchd for a send right to each named service and
# prints "<name> <kern_return_t>". A lookup sends no message to the service.
build_lookup_probe() {
  command -v cc >/dev/null 2>&1 || skip "C compiler unavailable"
  cat > "$TEST_PROJECT/lookup-probe.c" <<'C'
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <stdio.h>
int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_look_up(bootstrap_port, argv[i], &port);
    printf("LOOKUP %s %d\n", argv[i], (int)kr);
  }
  return 0;
}
C
  cc -o "$1" "$TEST_PROJECT/lookup-probe.c" >/dev/null 2>&1 || skip "cannot compile the lookup probe"
  "$1" com.apple.trustd >/dev/null 2>&1 || skip "cannot run the lookup probe"
}

lookup_code() {
  printf '%s\n' "$1" | sed -n "s/^LOOKUP $2 \\(-\\{0,1\\}[0-9][0-9]*\\)\$/\\1/p"
}

@test "keychain services kernel: SecurityServer and authd are unreachable without the grant; trustd stays reachable" {
  require_runtime_sandbox
  local probe="$HOME/project/lookup-probe" baseline name mode checked=0
  build_lookup_probe "$probe"
  # Unsandboxed baseline: which names this host registers at all.
  baseline="$("$probe" "${KEYCHAIN_SERVICE_NAMES[@]}" com.apple.trustd)"
  [ "$(lookup_code "$baseline" com.apple.trustd)" = 0 ] || skip "com.apple.trustd is not registered on this host"
  for mode in '' --strict --ro '--trust untrusted' --no-login-store \
      "--allow $HOME/Library/Keychains" "--strict --allow $HOME/Library/Keychains" \
      "--allow $HOME/Library"; do
    # shellcheck disable=SC2086
    run "$SCODE" $mode -C "$HOME/project" -- "$probe" "${KEYCHAIN_SERVICE_NAMES[@]}" com.apple.trustd
    echo "$mode: $output"
    [ "$status" -eq 0 ]
    for name in "${KEYCHAIN_SERVICE_NAMES[@]}"; do
      # Never reachable; where the host registers the name, the failure is
      # the sandbox denial (BOOTSTRAP_NOT_PRIVILEGED), not an unknown name.
      [ -n "$(lookup_code "$output" "$name")" ]
      [ "$(lookup_code "$output" "$name")" != 0 ]
      if [ "$(lookup_code "$baseline" "$name")" = 0 ]; then
        [ "$(lookup_code "$output" "$name")" = 1100 ]
        checked=$((checked + 1))
      fi
    done
    [ "$(lookup_code "$output" com.apple.trustd)" = 0 ]
    [ ! -s "$SECURITY_CALL_LOG" ]
  done
  [ "$(lookup_code "$baseline" com.apple.SecurityServer)" = 0 ]
  [ "$(lookup_code "$baseline" com.apple.authd)" = 0 ]
  [ "$checked" -gt 0 ]
}

@test "keychain services kernel: the applied grant keeps the services reachable, and losing the login keychain removes them" {
  require_runtime_sandbox
  local probe="$TEST_PROJECT/bin/claude" baseline mode name
  build_lookup_probe "$probe"
  baseline="$("$probe" "${KEYCHAIN_SERVICE_NAMES[@]}")"
  for mode in '' --strict; do
    # shellcheck disable=SC2086
    run "$SCODE" --login-store $mode -C "$HOME/project" -- claude "${KEYCHAIN_SERVICE_NAMES[@]}" com.apple.trustd
    echo "$mode granted: $output"
    [ "$status" -eq 0 ]
    for name in "${KEYCHAIN_SERVICE_NAMES[@]}"; do
      [ "$(lookup_code "$output" "$name")" = "$(lookup_code "$baseline" "$name")" ]
    done
    [ "$(lookup_code "$output" com.apple.trustd)" = 0 ]
  done
  rm -f "$HOME/Library/Keychains/login.keychain-db"
  for mode in '' --strict; do
    # shellcheck disable=SC2086
    run "$SCODE" --login-store $mode -C "$HOME/project" -- claude com.apple.SecurityServer com.apple.authd com.apple.trustd
    echo "$mode no keychain: $output"
    [ "$status" -eq 0 ]
    [ "$(lookup_code "$output" com.apple.SecurityServer)" = 1100 ]
    [ "$(lookup_code "$output" com.apple.authd)" = 1100 ]
    [ "$(lookup_code "$output" com.apple.trustd)" = 0 ]
  done
}

@test "keychain services: a preference file that cannot be classified declines the grant" {
  # /usr/bin/plutil cannot be replaced from a test, so the function is
  # taken from the launcher source and run against a stand-in plutil.
  local body stub="$TEST_PROJECT/plutil-stub" prefs="$TEST_PROJECT/prefs.plist" rc=0
  body="$(sed -n '/^recorded_keychain_from_preferences() {/,/^}/p' "$SCODE_SOURCE")"
  [[ -n "$body" ]]
  printf 'x\n' > "$prefs"

  # A plutil with -insert/-replace "-type value" in its help but no -type
  # query: lint succeeds, every -type query fails.
  cat > "$stub" <<'STUB'
#!/bin/bash
case "$1" in
  -help) echo "-insert keypath -type value"; echo "-replace keypath -type value"; exit 0 ;;
  -lint) exit 0 ;;
  *) echo "unrecognized option: $1" >&2; exit 1 ;;
esac
STUB
  chmod +x "$stub"
  eval "${body//\/usr\/bin\/plutil/$stub}"
  recorded_keychain_from_preferences "$prefs" DefaultKeychain || rc=$?
  [ "$rc" -eq 3 ]

  # An unreadable file is not "nothing recorded" either.
  if [[ "$(id -u)" -ne 0 ]]; then
    chmod 000 "$prefs"
    rc=0
    recorded_keychain_from_preferences "$prefs" DefaultKeychain || rc=$?
    chmod 600 "$prefs"
    [ "$rc" -eq 3 ]
  fi

  # The real plutil, where there is one, still reads a file that records nothing.
  if [[ -x /usr/bin/plutil ]] && [[ "$(printf '%s' '<plist version="1.0"><dict><key>k</key><array/></dict></plist>' |
      /usr/bin/plutil -type k - 2>/dev/null || true)" == array ]]; then
    eval "$body"
    printf '%s' '<plist version="1.0"><dict><key>Other</key><string>x</string></dict></plist>' > "$prefs"
    rc=0
    recorded_keychain_from_preferences "$prefs" DefaultKeychain || rc=$?
    [ "$rc" -eq 0 ]
  fi
  grep -q 'prefs_rc" -eq 3' "$SCODE_SOURCE"
}

@test "keychain services: --login-store on another command reports why it is not granted" {
  _SCODE_PLATFORM=darwin run "$SCODE" --dry-run --login-store -C "$TEST_PROJECT" -- codex --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"login-store access was requested but not granted: the command is not a login-store harness"* ]]
  [[ "$output" == *"(deny mach-lookup"* ]]

  # Without the flag nothing is reported for such a command.
  _SCODE_PLATFORM=darwin run "$SCODE" --dry-run -C "$TEST_PROJECT" -- codex --version
  [ "$status" -eq 0 ]
  [[ "$output" != *"login-store access was requested"* ]]
}
