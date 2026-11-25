#!/usr/bin/env bats
# Keychain service reach on macOS. One decision in the launcher yields both the
# login-store file grant and the Mach rule for the keychain daemons.
#
# The checks are profile text, bootstrap lookups that only ask launchd whether
# a name may be looked up, and one probe that asks authd for an authorization
# session with no rights (it shows nothing and asks for nothing). No test
# stores to or reads from a keychain or runs a Keychain tool.
load test_helper
load login_store_helper

KEYCHAIN_SERVICE_NAMES=(
  com.apple.securityd.xpc
  com.apple.authd
  com.apple.security.agent
  com.apple.security.agent.login
  com.apple.security.authhost
)

# The profile runs from its last "(version 1)" line to the "# Command:"
# trailer. Under kcov the tracer echoes multi-line values ahead of it, so
# text before that line is not part of the profile.
profile_text() {
  printf '%s\n' "$output" | sed '/^# Command:/,$d' |
    awk '/^\(version 1\)$/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }'
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
        # Without the grant the final rule closes the directory again.
        assert_access "$HOME/Library/Keychains/login.keychain-db" no
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
  # A dictionary with a key named "0", written as XML: older plutil
  # releases refuse to build it by key path.
  cat > "$prefs" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>DefaultKeychain</key><dict><key>0</key><dict>
<key>DbName</key><string>/nonexistent/x.keychain-db</string></dict></dict></dict></plist>
PLIST
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
    [[ "$text" == *"com.apple.authd"* ]]
    [[ "$text" == *"com.apple.SecurityServer"* ]]
    [[ "$text" == *"login.keychain-db"* ]]
  done
  text="$(tr '\n' ' ' < "$BATS_TEST_DIRNAME/../docs/security.md" | tr -d '`' | tr -s ' ')"
  [[ "$text" == *"com.apple.security.agent"*"com.apple.security.authhost"* ]]
  [[ "$text" == *"com.apple.securityd.xpc"* ]]
  [[ "$text" != *"com.apple.securityd.xpc) also stays reachable"* ]]
  [[ "$text" == *"without the login-store grant gives nothing"* ]]
  [[ "$text" != *"securityd reachable for that purpose"* ]]
  [[ "$text" == *"com.apple.SecurityServer (securityd) is left reachable on purpose"* ]]
  [[ "$text" == *"AuthorizationCreate fails inside the sandbox"* ]]
  [[ "$text" == *"The last rule of the profile denies reads and writes of the login keychain directories"* ]]
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

@test "keychain services: securityd is never denied; the login keychain directories are closed by the last rule" {
  # 0.6.9 denied com.apple.SecurityServer, and a client that loads the
  # system roots through the keychain API (Codex) had none: every HTTPS
  # request it made failed. The files are kept away instead.
  require_node
  local mode profile tail
  for mode in '' --strict --ro '--trust untrusted' --no-login-store "--allow $HOME/Library/Keychains" \
      "--allow $HOME/Library" "--allow-ro $HOME/Library/Keychains" "--strict --allow $HOME/Library/Keychains"; do
    # shellcheck disable=SC2086
    run_profile $mode -- true
    assert_keychain_services denied
    profile="$(profile_text)"
    [[ "$profile" != *'"com.apple.SecurityServer"'* ]]
    tail="${profile##*"(deny mach-lookup"}"
    [[ "$tail" == *'(deny file-read* file-write*'*"(subpath \"$HOME/Library/Keychains\")"* ]]
    assert_access "$HOME/Library/Keychains/login.keychain-db" no
  done
  # The array entries are bare names, one per line.
  local services
  services="$(sed -n '/^readonly DARWIN_KEYCHAIN_UI_SERVICES=(/,/^)/p' "$SCODE_SOURCE")"
  [[ "$services" == *$'\n'"  com.apple.authd"$'\n'* ]]
  [[ "$services" != *"com.apple.SecurityServer"* ]]
  # The project directory is no way in either.
  _SCODE_PLATFORM=darwin run "$SCODE" --dry-run -C "$HOME/Library/Keychains" -- true
  [ "$status" -eq 0 ]
  assert_access "$HOME/Library/Keychains/login.keychain-db" no
}

@test "keychain services: a keychain directory reached through a link is closed where the link leads" {
  local private="$TEST_PROJECT/private-home" outside="$TEST_PROJECT/outside-keychains" mode
  mkdir -p "$private/Library" "$private/project" "$outside"
  private="$(cd "$private" && pwd -P)"; outside="$(cd "$outside" && pwd -P)"
  : > "$outside/login.keychain-db"
  ln -s "$outside" "$private/Library/Keychains"
  for mode in '' --strict "--allow $outside"; do
    # shellcheck disable=SC2086
    HOME="$private" _SCODE_PLATFORM=darwin run "$SCODE" --dry-run $mode -C "$private/project" -- true
    [ "$status" -eq 0 ]
    local tail="${output##*"(deny mach-lookup"}"
    [[ "$tail" == *"(subpath \"$private/Library/Keychains\")"* ]]
    [[ "$tail" == *"(subpath \"$outside\")"* ]]
    [[ "$output" != *'"com.apple.SecurityServer"'* ]]
  done
}

@test "keychain services kernel: authd and the agents are unreachable without the grant; trustd and securityd stay reachable" {
  require_runtime_sandbox
  local probe="$HOME/project/lookup-probe" baseline name mode checked=0
  build_lookup_probe "$probe"
  # Unsandboxed baseline: which names this host registers at all.
  baseline="$("$probe" "${KEYCHAIN_SERVICE_NAMES[@]}" com.apple.trustd com.apple.SecurityServer)"
  [ "$(lookup_code "$baseline" com.apple.trustd)" = 0 ] || skip "com.apple.trustd is not registered on this host"
  for mode in '' --strict --ro '--trust untrusted' --no-login-store \
      "--allow $HOME/Library/Keychains" "--strict --allow $HOME/Library/Keychains" \
      "--allow $HOME/Library"; do
    # shellcheck disable=SC2086
    run "$SCODE" $mode -C "$HOME/project" -- "$probe" "${KEYCHAIN_SERVICE_NAMES[@]}" com.apple.trustd com.apple.SecurityServer
    echo "$mode: $output"
    # securityd is as reachable inside the sandbox as outside it.
    [ "$(lookup_code "$output" com.apple.SecurityServer)" = 0 ]
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
    [ "$(lookup_code "$output" com.apple.SecurityServer)" = 0 ]
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

@test "keychain services kernel: no authorization session can be made without the grant, and a login keychain file cannot be read" {
  # The dialog "A keychain cannot be found to store ..." is requested
  # through an authorization session. Making a session with no rights shows
  # nothing and asks nothing, so this is a passive check: it succeeds
  # outside the sandbox and must fail inside it.
  require_runtime_sandbox
  command -v cc >/dev/null 2>&1 || skip "C compiler unavailable"
  local probe="$HOME/project/authz-probe" mode
  cat > "$TEST_PROJECT/authz-probe.c" <<'C'
#include <Security/Authorization.h>
#include <stdio.h>
int main(int argc, char **argv) {
  AuthorizationRef ref = NULL;
  OSStatus status = AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, &ref);
  printf("AUTHZ %d\n", (int)status);
  if (ref != NULL) AuthorizationFree(ref, kAuthorizationFlagDefaults);
  if (argc > 1) {
    FILE *keychain = fopen(argv[1], "rb");
    printf("LOGIN-KEYCHAIN %s\n", keychain == NULL ? "unreadable" : "readable");
    if (keychain != NULL) fclose(keychain);
  }
  return 0;
}
C
  cc -o "$probe" "$TEST_PROJECT/authz-probe.c" -framework Security >/dev/null 2>&1 || skip "cannot compile the authorization probe"
  [[ "$("$probe")" == "AUTHZ 0"* ]] || skip "this host makes no authorization session outside the sandbox"
  [[ "$("$probe" "$HOME/Library/Keychains/login.keychain-db")" == *"LOGIN-KEYCHAIN readable"* ]]
  for mode in '' --strict --ro '--trust untrusted' --no-login-store "--allow $HOME/Library/Keychains" "--allow $HOME/Library"; do
    # shellcheck disable=SC2086
    run "$SCODE" $mode -C "$HOME/project" -- "$probe" "$HOME/Library/Keychains/login.keychain-db"
    echo "$mode: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTHZ "* ]]
    [[ "$output" != *"AUTHZ 0"* ]]
    [[ "$output" == *"LOGIN-KEYCHAIN unreadable"* ]]
  done
}

@test "keychain services kernel: no other route reaches a file in the login keychain directory" {
  # With securityd reachable, the file rule is the barrier. A hard link, a
  # clone, a symbolic link, the firmlinked path and a rename must all fail.
  require_runtime_sandbox
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS only"
  local mode
  printf 'synthetic\n' > "$HOME/Library/Keychains/login.keychain-db"
  for mode in '' --strict "--allow $HOME/Library/Keychains" "--allow $HOME/Library"; do
    # shellcheck disable=SC2086
    run "$SCODE" $mode -C "$HOME/project" -- /bin/sh -c '
      K="$HOME/Library/Keychains/login.keychain-db"
      cat "$K" >/dev/null 2>&1 && echo DIRECT-READ
      ln "$K" ./hard 2>/dev/null && cat ./hard >/dev/null 2>&1 && echo HARDLINK-READ
      cp -c "$K" ./clone 2>/dev/null && echo CLONE-READ
      cat "/System/Volumes/Data$K" >/dev/null 2>&1 && echo FIRMLINK-READ
      ln -s "$K" ./sym 2>/dev/null; cat ./sym >/dev/null 2>&1 && echo SYMLINK-READ
      mv "$K" ./moved 2>/dev/null && echo MOVED
      echo DONE'
    echo "$mode: $output"
    [[ "$output" == *"DONE"* ]]
    [[ "$output" != *"-READ"* ]]
    [[ "$output" != *"MOVED"* ]]
    rm -f "$HOME/project/hard" "$HOME/project/clone" "$HOME/project/sym" "$HOME/project/moved"
  done
  [ -f "$HOME/Library/Keychains/login.keychain-db" ]
}

@test "keychain services: a keychain directory path the profile cannot carry stops the launch" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS only"
  local private="$TEST_PROJECT/odd-home" target
  target="$TEST_PROJECT/odd"$'\t'"target"
  mkdir -p "$private/Library" "$private/project" "$target"
  private="$(cd "$private" && pwd -P)"
  ln -s "$target" "$private/Library/Keychains"
  HOME="$private" run "$SCODE" --dry-run -C "$private/project" -- true
  [ "$status" -ne 0 ]
  [[ "$output" != *'(subpath "")'* ]]
}

@test "keychain services: user keychains recorded in the preference file are closed too, by every link name" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS only"
  # A keychain outside ~/Library/Keychains that the account records (as the
  # default, the login keychain, or in the search list) is readable in
  # normal mode, and securityd is reachable: the final rule must name it.
  local prefs="$HOME/Library/Preferences/com.apple.security.plist" work="$HOME/work-keychains" hop="$HOME/hop"
  mkdir -p "$HOME/Library/Preferences" "$work"
  : > "$work/ci.keychain-db"; : > "$work/second.keychain-db"; : > "$work/old.keychain-db"
  /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DefaultKeychain -array "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DefaultKeychain.0.DbName -string "$work/ci.keychain-db" "$prefs"
  /usr/bin/plutil -insert DLDBSearchList -array "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0.DbName -string "~/work-keychains/second.keychain-db" "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.1 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.1.DbName -string "$work/old.keychain" "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.2 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.2.DbName -string "/Library/Keychains/System.keychain" "$prefs"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  local tail="${output##*"(deny mach-lookup"}" name
  for name in "$work/ci.keychain-db" "$work/second.keychain-db" "$work/old.keychain" "$work/old.keychain-db" "$HOME/Library/Keychains"; do
    [[ "$tail" == *"(subpath \"$name\")"* ]]
  done
  # The system domain is left readable: certificates are loaded from it.
  [[ "$tail" != *"/Library/Keychains/System.keychain"* ]]
  # Both names are closed whichever exists: macOS may open either, and a
  # recorded -db name closes its older twin as well.
  : > "$work/old.keychain"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  [[ "$tail" == *"(subpath \"$work/old.keychain\")"* ]]
  [[ "$tail" == *"(subpath \"$work/old.keychain-db\")"* ]]
  [[ "$tail" == *"(subpath \"$work/ci.keychain\")"* ]]
  rm -f "$work/old.keychain"

  # Review of 0.6.10: the Data-volume spelling of a user file is no system
  # keychain; an element without a DbName does not end the list; a list of
  # any length is read to its end; a dictionary is not a list.
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DLDBSearchList -array "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.1 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.1.DbName -string "/System/Volumes/Data$work/ci.keychain-db" "$prefs"
  local n
  for ((n = 2; n < 70; n++)); do
    /usr/bin/plutil -insert "DLDBSearchList.$n" -dictionary "$prefs"
    /usr/bin/plutil -insert "DLDBSearchList.$n.DbName" -string "$work/k$n.keychain-db" "$prefs"
  done
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  [[ "$tail" == *"ci.keychain-db\")"* ]]
  [[ "$tail" == *"(subpath \"$work/k69.keychain-db\")"* ]]
  cat > "$prefs" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>DLDBSearchList</key><dict><key>0</key><dict>
<key>DbName</key><string>$HOME/project</string></dict></dict></dict></plist>
PLIST
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  [[ "$tail" != *"(subpath \"$HOME/project\")"* ]]
  # A recorded name that is a directory names no keychain and closes nothing.
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DLDBSearchList -array "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0.DbName -string "/" "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.1 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.1.DbName -string "." "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.2 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.2.DbName -string "/missing/.." "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.3 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.3.DbName -string "$HOME/project/missing/.." "$prefs"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  [[ "$tail" != *'(subpath "/")'* ]]
  [[ "$tail" != *"(subpath \"$HOME/project\")"* ]]
  # A relative recorded name is read from the directory the command runs in.
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DLDBSearchList -array "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0.DbName -string "local.keychain-db" "$prefs"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  [[ "$tail" == *"/project/local.keychain-db\")"* ]]
  # A name with a control character whose -db file exists stops the launch.
  rm -f "$prefs"; /usr/bin/plutil -create xml1 "$prefs"
  /usr/bin/plutil -insert DLDBSearchList -array "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0 -dictionary "$prefs"
  /usr/bin/plutil -insert DLDBSearchList.0.DbName -string "$work/odd"$'\t'".keychain" "$prefs"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  : > "$work/odd"$'\t'".keychain-db"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -ne 0 ]
  rm -f "$work/odd"$'\t'".keychain-db"
  # A preference file that cannot be read may record keychains: the launch stops.
  if [[ "$(id -u)" -ne 0 ]]; then
    chmod 000 "$prefs"
    run "$SCODE" --dry-run -C "$HOME/project" -- true
    chmod 600 "$prefs"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot write the keychain rule"* ]]
  fi

  # The login keychain file itself may be a link: where it leads is closed.
  rm -f "$prefs"
  : > "$HOME/project/relocated.keychain-db"
  rm -f "$HOME/Library/Keychains/login.keychain-db"
  ln -s "$HOME/project/relocated.keychain-db" "$HOME/Library/Keychains/login.keychain-db"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  [[ "$tail" == *"/project/relocated.keychain-db\")"* ]]
  rm -f "$HOME/Library/Keychains/login.keychain-db"; : > "$HOME/Library/Keychains/login.keychain-db"

  # Two link hops: every name on the way is closed, not only the two ends.
  rm -f "$prefs"
  mv "$HOME/Library/Keychains" "$HOME/vault"
  ln -s "$HOME/vault" "$hop"
  ln -s "$hop" "$HOME/Library/Keychains"
  run "$SCODE" --dry-run -C "$HOME/project" -- true
  [ "$status" -eq 0 ]
  tail="${output##*"(deny mach-lookup"}"
  for name in "$HOME/Library/Keychains" "$hop" "$HOME/vault"; do
    [[ "$tail" == *"(subpath \"$name\")"* ]]
  done
}

@test "keychain services kernel: a writable parent cannot be renamed to give the keychain files another name" {
  # Review of 0.6.10: with --allow of ~/Library the parent could be renamed
  # and the file read under the new name. Ordinary writes must still work.
  require_runtime_sandbox
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS only"
  local probe="$HOME/project/rename-probe.sh" mode
  printf 'synthetic\n' > "$HOME/Library/Keychains/login.keychain-db"
  cat > "$probe" <<'SH'
#!/bin/sh
mv "$HOME/Library" "$HOME/L2" 2>/dev/null && echo RENAMED-PARENT
cat "$HOME/L2/Keychains/login.keychain-db" >/dev/null 2>&1 && echo READ-VIA-NEW-NAME
mv "$HOME/Library/Keychains" "$HOME/Library/K2" 2>/dev/null && echo RENAMED-DIRECTORY
: > "$HOME/Library/written" && echo WRITE-INSIDE-OK
mkdir "$HOME/project/d" && mv "$HOME/project/d" "$HOME/project/e" && echo PROJECT-OK
echo DONE
SH
  chmod +x "$probe"
  for mode in "--allow $HOME/Library" "--strict --allow $HOME/Library"; do
    # shellcheck disable=SC2086
    run "$SCODE" $mode -C "$HOME/project" -- "$probe"
    echo "$mode: $output"
    [[ "$output" == *"DONE"* ]]
    [[ "$output" != *"RENAMED-"* ]]
    [[ "$output" != *"READ-VIA-NEW-NAME"* ]]
    [[ "$output" == *"WRITE-INSIDE-OK"* ]]
    [[ "$output" == *"PROJECT-OK"* ]]
    [ -f "$HOME/Library/Keychains/login.keychain-db" ]
    mv "$HOME/project/e" "$HOME/project/gone-$RANDOM"
  done
}

@test "keychain services: a harness run through env with only home assignments is eligible; any other wrapper is not" {
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS only"
  require_node
  # codemux launches agy as `/usr/bin/env HOME=<private> XDG_*_HOME=... <agy>`.
  # 0.6.9 and earlier declined that as a wrapper, and the caller reached the
  # keychain through an explicit --allow, which the final rule now overrides.
  # The harness lies outside the project in every case, so the wrapper rule
  # is the only thing that can decline it.
  local harness="$TEST_PROJECT/bin/agy" private="$TEST_PROJECT/private" odd="$TEST_PROJECT/a=b"
  mkdir -p "$TEST_PROJECT/bin" "$private/Library" "$odd"
  cp /usr/bin/true "$harness"; cp /usr/bin/true "$odd/agy"
  ln -s "$HOME/Library/Keychains" "$private/Library/Keychains"
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$private" \
    "XDG_CONFIG_HOME=$private/.config" "XDG_CACHE_HOME=$private/.cache" "XDG_DATA_HOME=$private/.local/share" \
    "XDG_STATE_HOME=$private/.local/state" "$harness" --flag
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing login store"* ]]
  [[ "$output" != *"(deny mach-lookup"* ]]
  # Without the opt-in it is declined like any other launch.
  run "$SCODE" --dry-run -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny mach-lookup"* ]]
  # A HOME that does not lead to the login keychain leaves the harness
  # without a default keychain: declined, with the reason.
  mkdir -p "$TEST_PROJECT/bare"
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$TEST_PROJECT/bare" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not lead to the login keychain"* ]]
  [[ "$output" == *"(deny mach-lookup"* ]]
  # A private home with its own keychain preference file is declined (its
  # records were not judged); a link to the judged file is accepted.
  mkdir -p "$private/Library/Preferences" "$HOME/Library/Preferences"
  printf 'x' > "$private/Library/Preferences/com.apple.security.plist"
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has its own keychain preference file"* ]]
  [[ "$output" == *"(deny mach-lookup"* ]]
  rm -f "$private/Library/Preferences/com.apple.security.plist"
  /usr/bin/plutil -create xml1 "$HOME/Library/Preferences/com.apple.security.plist"
  ln -s "$HOME/Library/Preferences/com.apple.security.plist" "$private/Library/Preferences/com.apple.security.plist"
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing login store"* ]]
  rm -f "$private/Library/Preferences/com.apple.security.plist" "$HOME/Library/Preferences/com.apple.security.plist"
  # With the grant, the preference path of the harness's HOME is closed to
  # writes: the harness cannot record another default keychain afterward.
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing login store"* ]]
  [[ "$output" == *"(deny file-write*"*"(literal \"$private/Library/Preferences/com.apple.security.plist\")"* ]]
  [[ "$output" == *"(deny file-write-unlink"*"(literal \"$private/Library\")"* ]]
  # Preferences does not exist in this home: it may not be created (as a
  # link to somewhere writable), and the Keychains link may not be removed.
  [[ "$output" == *"(deny file-write*"*"(literal \"$private/Library/Preferences\")"* ]]
  [[ "$output" == *"(deny file-write-unlink"*"(literal \"$private/Library/Keychains\")"* ]]
  # Reached through a link, the path is closed under every name it has.
  ln -s "$private" "$TEST_PROJECT/alias-home"
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$TEST_PROJECT/alias-home" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing login store"* ]]
  [[ "$output" == *"(literal \"$TEST_PROJECT/alias-home/Library/Preferences/com.apple.security.plist\")"* ]]
  [[ "$output" == *"(literal \"$private/Library/Preferences/com.apple.security.plist\")"* ]]
  # A private Keychains directory of its own that only links the login
  # file is not the judged directory: a recorded ~/Library/Keychains/<name>
  # would be another file there.
  mkdir -p "$TEST_PROJECT/partial/Library/Keychains"
  ln -s "$HOME/Library/Keychains/login.keychain-db" "$TEST_PROJECT/partial/Library/Keychains/login.keychain-db"
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$TEST_PROJECT/partial" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not lead to the login keychain"* ]]
  # A block over the harness's HOME hides the keychain that was judged.
  run "$SCODE" --dry-run --login-store --block "$private" -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a block covers the keychain path under the HOME given to the harness"* ]]
  [[ "$output" == *"(deny mach-lookup"* ]]
  # A HOME with a control character is declined and never echoed.
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "HOME=/nonexistent/"$'\033'"]0;x" "$harness"
  [[ "$output" == *"contains a control character"* ]]
  [[ "$output" != *$'\033'"]0;x"* ]]
  # Each of these stays ineligible: another assignment, an env option, a
  # relative harness path, a bare env, a path env would read as an
  # assignment, and a shell wrapper.
  local n=0
  check_ineligible() {
    n=$((n + 1))
    run "$SCODE" --dry-run --login-store -C "$HOME/project" -- "$@"
    echo "$n: $status $*"
    [ "$status" -eq 0 ]
    [[ "$output" != *"allowing login store"* ]]
    [[ "$output" == *"(deny mach-lookup"* ]]
  }
  check_ineligible /usr/bin/env "HOME=$private" DYLD_INSERT_LIBRARIES=/x "$harness"
  check_ineligible /usr/bin/env -i "HOME=$private" "$harness"
  check_ineligible /usr/bin/env "$harness"
  check_ineligible /usr/bin/env "HOME=$private" "$odd/agy" /bin/sh
  check_ineligible /bin/sh -c "$harness"
  # A link that resolves into a directory with "=" in its name: the
  # resolved path would be read by env as an assignment.
  ln -s "$odd" "$TEST_PROJECT/tools"
  check_ineligible /usr/bin/env "HOME=$private" "$TEST_PROJECT/tools/agy" /bin/sh
  # An empty or relative HOME is no home the keychain was checked under.
  check_ineligible /usr/bin/env "HOME=" "$harness"
  (cd "$TEST_PROJECT" && check_ineligible /usr/bin/env "HOME=private" "$harness")
  # Home assignments without HOME itself leave the judged HOME in force.
  run "$SCODE" --dry-run --login-store -C "$HOME/project" -- /usr/bin/env "XDG_CONFIG_HOME=$private/.config" "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowing login store"* ]]
  (cd "$TEST_PROJECT" && check_ineligible /usr/bin/env "HOME=$private" bin/agy)
  # A harness inside the project stays ineligible through env too.
  mkdir -p "$HOME/project/bin"; cp /usr/bin/true "$HOME/project/bin/agy"
  check_ineligible /usr/bin/env "HOME=$private" "$HOME/project/bin/agy"
}

@test "keychain services kernel: env runs the judged harness binary, and the grant reaches the keychain through the private home" {
  require_runtime_sandbox
  [[ "$(uname -s)" == "Darwin" ]] || skip "macOS only"
  local harness="$TEST_PROJECT/bin/agy" private="$TEST_PROJECT/private"
  mkdir -p "$TEST_PROJECT/bin" "$private/Library"
  printf 'synthetic\n' > "$HOME/Library/Keychains/login.keychain-db"
  ln -s "$HOME/Library/Keychains" "$private/Library/Keychains"
  # A stand-in harness: a compiled program that reads the keychain file
  # under its own HOME and reports what HOME it was given.
  command -v cc >/dev/null 2>&1 || skip "C compiler unavailable"
  cat > "$TEST_PROJECT/agy.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
int main(void) {
  char path[4096];
  const char *home = getenv("HOME");
  snprintf(path, sizeof path, "%s/Library/Keychains/login.keychain-db", home ? home : "");
  FILE *file = fopen(path, "rb");
  printf("HOME=%s KEYCHAIN=%s\n", home ? home : "", file ? "readable" : "unreadable");
  /* What a harness could try after the grant: make the missing Preferences
     directory a link to somewhere writable, or swap the Keychains link. */
  snprintf(path, sizeof path, "%s/Library/Preferences", home ? home : "");
  printf("PREFERENCES-LINK=%s\n", symlink("/tmp", path) == 0 ? "created" : "denied");
  printf("PREFERENCES-DIR=%s\n", mkdir(path, 0700) == 0 ? "created" : "denied");
  snprintf(path, sizeof path, "%s/Library/Keychains", home ? home : "");
  printf("KEYCHAINS-UNLINK=%s\n", unlink(path) == 0 ? "removed" : "denied");
  return 0;
}
C
  cc -o "$harness" "$TEST_PROJECT/agy.c" >/dev/null 2>&1 || skip "cannot compile the stand-in harness"
  run "$SCODE" --login-store -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HOME=$private KEYCHAIN=readable"* ]]
  [[ "$output" == *"PREFERENCES-LINK=denied"* ]]
  [[ "$output" == *"PREFERENCES-DIR=denied"* ]]
  [[ "$output" == *"KEYCHAINS-UNLINK=denied"* ]]
  [ -L "$private/Library/Keychains" ]
  [ ! -e "$private/Library/Preferences" ]
  # Without the opt-in the same launch cannot read it.
  run "$SCODE" -C "$HOME/project" -- /usr/bin/env "HOME=$private" "$harness"
  [[ "$output" == *"KEYCHAIN=unreadable"* ]]
}
