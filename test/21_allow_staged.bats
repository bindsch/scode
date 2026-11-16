#!/usr/bin/env bats
load test_helper

staged_fixture() {
  mkdir -p "$TEST_PROJECT/home/project" "$TEST_PROJECT/home/store"
  export HOME="$(cd "$TEST_PROJECT/home" && pwd -P)"
  export SCODE_CONFIG="$TEST_PROJECT/empty.yaml"
  : > "$SCODE_CONFIG"
}

@test "allow-staged: help, missing argument, invalid path, and file-only validation" {
  staged_fixture
  run "$SCODE" --help
  [[ "$output" == *"--allow-staged PATH"* ]]
  run "$SCODE" --allow-staged
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing argument"* ]]
  run "$SCODE" --allow-staged $'/bad\npath' -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"control characters"* ]]
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --allow-staged "$HOME/store" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a file"* ]]
}

@test "allow-staged: Linux refuses CLI and user-config patterns in both modes" {
  staged_fixture
  local mode
  for mode in '' --strict; do
    run env _SCODE_PLATFORM=linux "$SCODE" --dry-run $mode --allow-staged "$HOME/store/login" -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"macOS-only"*"future staging filenames"* ]]
    printf 'allowed_staged:\n  - %s\n' "$HOME/store/login" > "$SCODE_CONFIG"
    run env _SCODE_PLATFORM=linux "$SCODE" --dry-run $mode -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"macOS-only"* ]]
    : > "$SCODE_CONFIG"
  done
}

@test "allow-staged: repeated relative and linked grants resolve and project config adds no authority" {
  staged_fixture
  ln -s "$HOME/store" "$HOME/project/link"
  printf 'allowed_staged:\n  - ../store/ignored\n' > "$HOME/project/.scode.yaml"
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$HOME/project" \
    --allow-staged link/login --allow-staged ../store/owner -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring project config allowed_staged"* ]]
  [[ "$output" == *"(literal \"$HOME/store/login\")"* ]]
  [[ "$output" == *"(literal \"$HOME/store/owner\")"* ]]
  [[ "$output" != *"(literal \"$HOME/store/ignored\")"* ]]
}

@test "allow-staged: CLI blocks beat user config, including a staging sibling" {
  staged_fixture
  printf 'allowed_staged:\n  - %s\n' "$HOME/store/login" > "$SCODE_CONFIG"
  local block
  # The kernel matches the staged regex without regard to case, so a block
  # spelled in another case names the same grant and must also win.
  local upper_home
  upper_home="$(printf '%s' "$HOME" | LC_ALL=C tr '[:lower:]' '[:upper:]')"
  for block in "$HOME/store" "$HOME/store/login" "$HOME/store/login.tmp.1234abcd" \
    "$HOME/store/LOGIN.TMP.1234ABCD" "$upper_home/STORE/LOGIN"; do
    run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$HOME/project" --block "$block" -- true
    [ "$status" -eq 0 ]
    [[ "$output" != *"Explicit staged-file grant"* ]]
    run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$HOME/project" \
      --block "$block" --allow-staged "$HOME/store/login" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"Explicit staged-file grant"* ]]
  done
}

@test "allow-staged: symlinked base files are refused for CLI and user config" {
  staged_fixture
  printf fixture > "$HOME/store/target"
  ln -s "$HOME/store/target" "$HOME/project/link"
  ln -s "$HOME/store/missing" "$HOME/project/dangling"
  local base source
  # A trailing slash must not hide the final link from the refusal.
  for base in link dangling link/ dangling// ; do
    for source in cli config; do
      : > "$SCODE_CONFIG"
      local args=()
      if [[ "$source" == cli ]]; then args=(--allow-staged "$base")
      else printf 'allowed_staged:\n  - %s\n' "$base" > "$SCODE_CONFIG"; fi
      run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$HOME/project" "${args[@]}" -- true
      [ "$status" -eq 1 ]
      [[ "$output" == *"refuses a symlinked base file: $base"* ]]
    done
  done
  [ "$(cat "$HOME/store/target")" = fixture ]
  [ ! -e "$HOME/store/missing" ]
}

@test "allow-staged runtime: atomic replacement succeeds and all other sibling names stay denied" {
  require_runtime_sandbox
  staged_fixture
  local mode base
  base="$HOME/store/login"
  for mode in '' --strict '--trust untrusted'; do
    run "$SCODE" $mode -C "$HOME/project" --block "$HOME/store" \
      --allow-staged "$base" --allow-staged "$HOME/store/owner" -- /bin/sh -eu -c '
        for base in "$@"; do
          printf first > "$base.tmp.0123abcd"
          /bin/mv -f "$base.tmp.0123abcd" "$base"
          test "$(/bin/cat "$base")" = first
          printf second > "$base.tmp.89abcdef"
          /bin/mv -f "$base.tmp.89abcdef" "$base"
          test "$(/bin/cat "$base")" = second
          # The macOS kernel matches SBPL path regexes case-insensitively, so an
          # uppercase hex suffix is inside the grant; every other name stays denied.
          # A name that only differs by a trailing newline is a different file.
          newline_name="$base.tmp.0123abcd
"
          if (printf denied > "$newline_name") 2>/dev/null; then echo "unexpected grant: trailing newline"; exit 13; fi
          for suffix in .tmp.zzzzzzzz .tmp.123456789 .tmp.ABCDEFG1 .tmp.abcdefg1 .tmp.1234567 .tmp.12345678.extra .other; do
            if (printf denied > "$base$suffix") 2>/dev/null; then echo "unexpected grant: $suffix"; exit 10; fi
          done
        done
        if (printf denied > "${1%/*}/another.tmp.1234abcd") 2>/dev/null; then exit 11; fi
        if /bin/ls "${1%/*}" >/dev/null 2>&1; then echo "unexpected directory listing"; exit 12; fi
        printf "atomic replacements passed\n"
      ' sh "$HOME/store/owner" "$base"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"atomic replacements passed"* ]]
  done
}

@test "allow-staged runtime: escaped paths grant only regular files and no directory contents" {
  require_runtime_sandbox
  staged_fixture
  local mode base other
  base="$HOME/store/"'login.[x](a)+{b}^$|?*\"'
  other="$HOME/store/"'loginX[x](a)+{b}^$|?*\"'
  for mode in '' --strict; do
    run "$SCODE" $mode -C "$HOME/project" --block "$HOME/store" --allow-staged "$base" \
      -- /bin/sh -eu -c '
        printf escaped > "$1.tmp.a1b2c3d4"
        mv "$1.tmp.a1b2c3d4" "$1"
        test "$(cat "$1")" = escaped
        ! (printf denied > "$2.tmp.a1b2c3d4")
        ! mkdir "$1.tmp.abcdef01"
        ! ls "${1%/*}"
      ' sh "$base" "$other"
    echo "$output"
    [ "$status" -eq 0 ]
  done
}

@test "allow-staged runtime: nested blocks and read-only ancestors preserve reads and write caps" {
  require_runtime_sandbox
  staged_fixture
  mkdir "$HOME/.aws"
  printf secret > "$HOME/.aws/secret"
  printf initial > "$HOME/.aws/login"
  local mode
  for mode in '' --strict; do
    run "$SCODE" $mode -C "$HOME/project" --allow-ro "$HOME" --allow-staged "$HOME/.aws/login" \
      -- /bin/sh -eu -c '
        test "$(cat "$1/login")" = initial
        ! cat "$1/secret"
        ! (printf denied > "$1/login")
        ! (printf denied > "$1/login.tmp.1234abcd")
      ' sh "$HOME/.aws"
    echo "$output"
    [ "$status" -eq 0 ]
  done
}

@test "allow-staged: resolved control characters and Grok mandatory block conflicts refuse" {
  staged_fixture
  mkdir "$HOME/"$'bad\nname'
  ln -s "$HOME/"$'bad\nname' "$HOME/project/link"
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$HOME/project" --allow-staged link/file -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"control characters"* ]]
  printf 'grok_defense: true\n' > "$SCODE_CONFIG"
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$HOME/project" --allow-staged .env -- grok
  [ "$status" -eq 1 ]
  [[ "$output" == *"grok_defense conflicts with staged allowed path"* ]]
}

@test "allow-staged runtime: JSON and legacy logs record the bounded base path" {
  require_runtime_sandbox
  staged_fixture
  run "$SCODE" --strict -C "$HOME/project" --allow-staged "$HOME/store/login" \
    --log "$HOME/project/run.log" -- /usr/bin/true
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F "\"allowed_staged\":[\"$HOME/store/login\"]" "$HOME/project/run.log"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -Fx "# allowed_staged: $HOME/store/login" "$HOME/project/run.log"
  [ "$status" -eq 0 ]
}

@test "allow-staged runtime: config grants work and read-only invariants cap writes" {
  require_runtime_sandbox
  staged_fixture
  printf initial > "$HOME/store/login"
  printf 'allowed_staged:\n  - %s\n' "$HOME/store/login" > "$SCODE_CONFIG"
  local mode
  for mode in '' --strict; do
    run "$SCODE" $mode -C "$HOME/project" --block "$HOME/store" --allow-staged "$HOME/store/login" \
      --allow-ro "$HOME/store" -- /bin/sh -eu -c '
        cat "$1/login"
        ! (printf denied > "$1/login")
        ! (printf denied > "$1/login.tmp.1234abcd")
      ' sh "$HOME/store"
    [ "$status" -eq 0 ]
    run "$SCODE" $mode -C "$HOME/project" --ro --allow-staged "$HOME/project/login" \
      -- /bin/sh -c '! (printf denied > login.tmp.1234abcd) && ! (printf denied > login)'
    [ "$status" -eq 0 ]
    run "$SCODE" $mode -C "$HOME/project" -- /bin/sh -eu -c \
      'printf config > "$1.tmp.1234abcd"; mv "$1.tmp.1234abcd" "$1"' sh "$HOME/store/login"
    echo "$output"
    [ "$status" -eq 0 ]
  done
}

@test "allow-staged runtime: blocked parent keeps base and staging files non-executable" {
  require_runtime_sandbox
  staged_fixture
  local base="$HOME/store/login" mode
  # Native executables avoid shell fallback interpreting a denied script.
  cp /usr/bin/true "$base"
  cp /usr/bin/true "$base.tmp.1234abcd"
  cp /usr/bin/true "$HOME/store/explicit"
  chmod +x "$base" "$base.tmp.1234abcd" "$HOME/store/explicit"
  for mode in '' --strict '--trust untrusted'; do
    run "$SCODE" $mode -C "$HOME/project" --block "$HOME/store" \
      --allow-staged "$base" --allow "$HOME/store/explicit" -- /bin/sh -eu -c '
        for path in "$1" "$1.tmp.1234abcd"; do
          /bin/cat "$path" >/dev/null
          if "$path"; then echo "unexpected execution: $path"; exit 10; fi
        done
        "$2"
        printf "staged execution denied\n"
      ' sh "$base" "$HOME/store/explicit"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"staged execution denied"* ]]
  done
}

@test "allow-staged: logging reference documents staged and automatic login grants" {
  local doc
  doc="$(cat "$BATS_TEST_DIRNAME/../docs/logging.md")"
  [[ "$doc" == *'`allowed_staged` | array of strings | Staged-file base paths'* ]]
  [[ "$doc" == *'`# allowed_staged:`'* ]]
  [[ "$doc" == *'opt-in macOS login-store directory grants in normal and strict modes'* ]]
  [[ "$doc" == *'security preference file from an enabled macOS login-store grant'* ]]
}
