#!/usr/bin/env bats
# Final guards must preserve the same exceptions as the initial policy.
load test_helper

setup_final_policy_home() {
  FHOME="$TEST_PROJECT/home"
  mkdir -p "$FHOME/project/nested" "$FHOME/holder/allowed" "$FHOME/holder/private"
  FHOME="$(cd -P "$FHOME" && pwd -P)"
  export SCODE_CONFIG="$FHOME/empty.yaml"
  : > "$SCODE_CONFIG"
  ln -s "$FHOME/project" "$FHOME/holder/allowed/link"
  ln -s holder/allowed/link "$FHOME/.aws"
  ln -s project/nested "$FHOME/.ssh"
  printf 'project-source\n' > "$FHOME/project/source"
  printf 'blocked-fixture\n' > "$FHOME/project/nested/secret"
  printf 'blocked-fixture\n' > "$FHOME/holder/private/secret"
  printf 'allowed-fixture\n' > "$FHOME/holder/allowed/source"
}

@test "macOS: every re-denial preserves the project exception through an intermediate link" {
  setup_final_policy_home
  local mode access tail
  for mode in '' --strict; do
    for access in --rw --ro; do
      run env HOME="$FHOME" _SCODE_PLATFORM=darwin "$SCODE" --dry-run ${mode:+"$mode"} "$access" \
        -C "$FHOME/project" --block "$FHOME/holder" --allow "$FHOME/holder/allowed" -- /bin/cat source
      [ "$status" -eq 0 ]
      # Initial default-mode denies may precede the project grant. No pass
      # after that grant may deny its built-in parent again.
      tail="${output#*; Project directory (}"
      [[ "$tail" != *"(deny file-read* file-write* process-exec"$'\n'"  (subpath \"$FHOME/.aws\")"* ]]
      [[ "$tail" == *"  (subpath \"$FHOME/project/nested\")"* ]]
      [[ "$tail" == *"; Final custom-policy blocks"* ]]
    done
  done
}

@test "Linux: final masks preserve the project exception and nested blocks through a link" {
  setup_final_policy_home
  local mode access tail
  for mode in '' --strict; do
    for access in --rw --ro; do
      run env HOME="$FHOME" _SCODE_PLATFORM=linux "$SCODE" --dry-run ${mode:+"$mode"} "$access" \
        -C "$FHOME/project" --block "$FHOME/holder" --allow "$FHOME/holder/allowed" -- /bin/cat source
      [ "$status" -eq 0 ]
      tail="${output##* $FHOME/project $FHOME/project }"
      [[ "$tail" != *"--tmpfs $FHOME/project "* ]]
      [[ "$tail" == *"--tmpfs $FHOME/project/nested "* ]]
      if [[ -z "$mode" ]]; then
        [[ "$tail" == *"--tmpfs $FHOME/holder "*"--bind $FHOME/holder/allowed $FHOME/holder/allowed"* ]]
      else
        # A parent outside the strict mounts is already absent.
        [[ "$output" == *"--bind $FHOME/holder/allowed $FHOME/holder/allowed"* ]]
      fi
    done
  done
}

@test "runtime: final child restores preserve project access, nested blocks, and read-only" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  setup_final_policy_home
  local mode access
  for mode in '' --strict; do
    for access in --rw --ro; do
      HOME="$FHOME" run "$SCODE" ${mode:+"$mode"} "$access" --no-net \
        -C "$FHOME/project" --block "$FHOME/holder" --allow "$FHOME/holder/allowed" -- \
        /bin/sh -c '
          cat source || exit 11
          cat "$HOME/holder/allowed/source" || exit 12
          cat nested/secret 2>/dev/null && exit 13
          cat "$HOME/holder/private/secret" 2>/dev/null && exit 14
          if [ "$1" = --ro ]; then
            (echo changed > source) 2>/dev/null && exit 15
          else
            echo writable > written || exit 16
          fi
          echo allowed-write > "$HOME/holder/allowed/written" || exit 17
          exit 0
        ' sh "$access"
      [ "$status" -eq 0 ]
      [[ "$output" == *project-source*allowed-fixture* ]]
      [[ "$output" != *blocked-fixture* ]]
    done
  done
}

@test "strict macOS: private temp grants cannot reopen a linked built-in block" {
  setup_final_policy_home
  run env HOME="$FHOME" _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$FHOME/project" -- true
  [ "$status" -eq 0 ]
  local private_temp
  private_temp="$(printf '%s\n' "$output" | sed -n 's/^  (subpath "\(.*\/scode\.[0-9]*\.dry-run\)")$/\1/p' | head -1)"
  [ -n "$private_temp" ]
  # The dry-run directory is never created. A dangling link still needs a
  # denial so the sandbox cannot create the blocked target inside its grant.
  ln -s "$private_temp/credentials" "$FHOME/.gnupg"
  run env HOME="$FHOME" _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$FHOME/project" -- true
  [ "$status" -eq 0 ]
  local tail="${output##*; Built-in blocks inside granted paths}"
  [[ "$tail" == *"(subpath \"$FHOME/.gnupg\")"*"(subpath \"$private_temp/credentials\")"* ]]
}

# Exercise the real profile emitter with a deterministic private temp path.
# The CLI creates a fresh random directory, so it cannot contain a fixture
# credential before launch. Load function definitions only, without main.
render_private_temp_profile() {
  source <(awk '/^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/ { emit=1 } emit { print } /^}/ { emit=0 }' "$SCODE_SOURCE")
  ALL_BLOCKED=("$FHOME/.gnupg")
  ALL_BLOCKED_SOURCES=(default)
  ALL_BLOCKED_SPELLINGS=("$FHOME/.gnupg"$'\n'"$FHOME/temp/credentials"$'\n')
  ALL_ALLOWED=()
  ALL_ALLOWED_SOURCES=()
  HARNESS_STRICT_RO=()
  DARWIN_STRICT_SYSTEM_PATHS=(/usr /bin /sbin /System /Library /dev /private/etc /private/var/db /private/var/run /private/var/select)
  SAFE_DARWIN_TMPDIR="$FHOME/temp"
  SCODE_NO_SANDBOX_JS=""
  generate_strict_profile "$FHOME/project" rw off "${ALL_BLOCKED[@]}"
}

@test "macOS runtime: private temp keeps blocked credentials hidden and ordinary temp writable" {
  require_runtime_sandbox
  setup_final_policy_home
  mkdir -p "$FHOME/temp/credentials"
  ln -s temp/credentials "$FHOME/.gnupg"
  printf 'blocked-fixture\n' > "$FHOME/temp/credentials/secret"
  local profile
  profile="$(render_private_temp_profile)"
  cd "$FHOME/project"
  run /usr/bin/sandbox-exec -p "$profile" /bin/sh -c '
    cat "$1/credentials/secret" 2>/dev/null && exit 11
    (echo changed > "$1/credentials/secret") 2>/dev/null && exit 12
    echo ordinary-temp > "$1/ordinary" || exit 13
    cat "$1/ordinary"
  ' sh "$FHOME/temp"
  [ "$status" -eq 0 ]
  [[ "$output" == *ordinary-temp* ]]
  [[ "$output" != *blocked-fixture* ]]
}

@test "strict Linux: custom blocks also mask system read grants" {
  setup_final_policy_home
  run env HOME="$FHOME" _SCODE_PLATFORM=linux "$SCODE" --dry-run --strict \
    -C "$FHOME/project" --block /usr/bin/false -- /bin/sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ro-bind /usr /usr "*"--ro-bind /dev/null /usr/bin/false "* ]]
}

@test "Linux runtime: a custom block inside a system grant remains masked" {
  require_linux_bwrap
  setup_final_policy_home
  HOME="$FHOME" run "$SCODE" --strict --no-net -C "$FHOME/project" \
    --block /usr/bin/false -- /bin/sh -c 'test ! -s /usr/bin/false'
  [ "$status" -eq 0 ]
}

@test "Linux: a built-in link inside the project cannot mask its own project target" {
  setup_final_policy_home
  # A block name is inside HOME, but its canonical mask target is HOME itself.
  ln -snf "$FHOME" "$FHOME/holder/allowed/link"
  local access tail
  for access in --rw --ro; do
    run env HOME="$FHOME" _SCODE_PLATFORM=linux "$SCODE" --dry-run "$access" \
      -C "$FHOME" --block "$FHOME/holder" --allow "$FHOME/holder/allowed" -- /bin/sh
    [ "$status" -eq 0 ]
    # Skip the initial HOME mask, then inspect after the first project
    # restoration. A later ro-bind must not hide a bad earlier re-mask.
    tail="${output#*--tmpfs $FHOME }"
    tail="${tail#* $FHOME $FHOME }"
    [[ "$tail" != *"--tmpfs $FHOME "* ]]
  done
}

@test "runtime: a built-in link inside HOME preserves HOME as the selected project" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  setup_final_policy_home
  ln -snf "$FHOME" "$FHOME/holder/allowed/link"
  local mode access
  for mode in '' --strict; do
    for access in --rw --ro; do
      HOME="$FHOME" run "$SCODE" ${mode:+"$mode"} "$access" --no-net \
        -C "$FHOME" --block "$FHOME/holder" --allow "$FHOME/holder/allowed" -- /bin/sh -c '
          cat project/source || exit 11
          cat holder/allowed/source || exit 12
          cat project/nested/secret 2>/dev/null && exit 13
          cat holder/private/secret 2>/dev/null && exit 14
          if [ "$1" = --ro ]; then
            (echo changed > project/source) 2>/dev/null && exit 15
          else
            echo writable > written || exit 16
          fi
          exit 0
        ' sh "$access"
      [ "$status" -eq 0 ]
      [[ "$output" == *project-source*allowed-fixture* ]]
    done
  done
}
