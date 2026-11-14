#!/usr/bin/env bats
load test_helper

ro_fixture() {
  mkdir -p "$TEST_PROJECT/home/project" "$TEST_PROJECT/home/store/sub"
  export HOME="$TEST_PROJECT/home"
  export SCODE_CONFIG="$TEST_PROJECT/empty.yaml"
  : > "$SCODE_CONFIG"
  printf 'read-only-data\n' > "$HOME/store/sub/data"
  printf '#!/bin/sh\nprintf executable-ok\n' > "$HOME/store/sub/tool"
  chmod +x "$HOME/store/sub/tool"
}

@test "allow-ro: help, missing argument, and control-character validation" {
  run "$SCODE" --help
  [[ "$output" == *"--allow-ro PATH"* ]]
  run "$SCODE" --allow-ro
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing argument"* ]]
  run "$SCODE" --allow-ro $'/bad\npath' -- /usr/bin/true
  [ "$status" -ne 0 ]
  [[ "$output" == *"control characters"* ]]
}

@test "allow-ro: both dry-run backends resolve repeated relative and linked grants" {
  ro_fixture
  ln -s "$HOME/store" "$HOME/project/link"
  local platform mode path
  path="$(cd "$HOME/store/sub" && pwd -P)"
  for platform in darwin linux; do
    for mode in '' --strict; do
      run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/project" \
        --block "$HOME/store" --allow-ro link/sub/tool --allow-ro ../store/sub/data -- /usr/bin/true
      [ "$status" -eq 0 ]
      if [[ "$platform" == darwin ]]; then
        [[ "$output" == *"(allow file-read* process-exec (subpath \"$path/tool\"))"* ]]
        [[ "$output" == *"(deny file-write* (subpath \"$path/data\"))"* ]]
      else
        [[ "$output" == *"--ro-bind $path/tool $path/tool"* ]]
        [[ "$output" == *"--ro-bind $path/data $path/data"* ]]
      fi
    done
  done
}

@test "allow-ro: config cannot override a CLI block; CLI can reopen reads" {
  ro_fixture
  printf 'allowed_ro:\n  - %s\n' "$HOME/store" > "$SCODE_CONFIG"
  run "$SCODE" --dry-run -C "$HOME/project" --block "$HOME/store/sub" -- /usr/bin/true
  [ "$status" -eq 0 ]
  [[ "$output" != *"Explicit read-only grant"* ]]
  run "$SCODE" --dry-run -C "$HOME/project" --block "$HOME/store/sub" --allow-ro "$HOME/store" -- /usr/bin/true
  [ "$status" -eq 0 ]
  [[ "$output" == *"Explicit read-only grant"* || "$output" == *"--ro-bind $HOME/store"* ]]
}

@test "allow-ro: project config adds no authority" {
  ro_fixture
  printf 'allowed_ro:\n  - %s\n' "$HOME/store" > "$HOME/project/.scode.yaml"
  run "$SCODE" --dry-run --strict -C "$HOME/project" -- /usr/bin/true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring project config allowed_ro"* ]]
  [[ "$output" != *"Explicit read-only grant"* ]]
}

@test "allow-ro: resolved symlink targets reject control characters on both backends" {
  ro_fixture
  mkdir "$HOME/"$'bad\nname'
  ln -s "$HOME/"$'bad\nname' "$HOME/project/link"
  local platform
  for platform in darwin linux; do
    run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run -C "$HOME/project" --allow-ro link -- /usr/bin/true
    [ "$status" -ne 0 ]
    [[ "$output" == *"control characters"* ]]
  done
}

@test "allow-ro runtime: blocked child reads and executes but cannot write; sibling stays hidden" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  ro_fixture
  printf secret > "$HOME/store/secret"
  local mode
  for mode in '' --strict; do
    run "$SCODE" $mode -C "$HOME/project" --block "$HOME/store" --allow-ro "$HOME/store/sub" \
      -- /bin/sh -c 'cat "$1/data" && "$1/tool" && ! cat "$1/../secret" && ! echo bad > "$1/data" && ! touch "$1/new"' sh "$HOME/store/sub"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *read-only-data*executable-ok* ]]
  done
}

@test "allow-ro runtime: default block, config grant, and writable overlap stay read-only" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  ro_fixture
  mkdir -p "$HOME/.aws"
  printf fixture > "$HOME/.aws/data"
  printf 'allowed_ro:\n  - %s\n' "$HOME/.aws" > "$SCODE_CONFIG"
  local mode
  for mode in '' --strict; do
    run "$SCODE" $mode -C "$HOME/project" --allow "$HOME" -- /bin/sh -c \
      'cat "$1/data" && ! echo changed > "$1/data"' sh "$HOME/.aws"
    [ "$status" -eq 0 ]
    [[ "$output" == *fixture* ]]
  done
}

@test "allow-ro runtime: synthetic HOME can read an exact account-home file" {
  [[ "$(uname -s)" == Darwin ]] || skip "macOS account-home block"
  require_runtime_sandbox
  mkdir -p "$BATS_TEST_DIRNAME/../scratch"
  local account_fixture
  account_fixture="$(mktemp -d "$BATS_TEST_DIRNAME/../scratch/ro.XXXXXXXX")"
  track_cleanup "$account_fixture"
  printf account-fixture > "$account_fixture/data"
  ro_fixture
  run "$SCODE" --strict -C "$HOME/project" --allow-ro "$account_fixture/data" -- /bin/sh -c \
    'cat "$1" && ! echo changed > "$1"' sh "$account_fixture/data"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *account-fixture* ]]
}

@test "allow-ro runtime: read-only project can reopen a custom parent block" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  ro_fixture
  printf project-data > "$HOME/project/data"
  run "$SCODE" --strict --ro -C "$HOME/project" --block "$HOME" --allow-ro "$HOME/project" \
    -- /bin/sh -c 'cat data && ! echo changed > data'
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *project-data* ]]
}

@test "allow-ro: every covering custom block needs its own project read exception" {
  ro_fixture
  mkdir -p "$HOME/store/sub/project"
  ln -s "$HOME/store/sub" "$HOME/blocked-link"
  local platform mode block grant
  for platform in darwin linux; do
    for mode in '' --strict; do
      for block in "$HOME/store/sub" "$HOME/store/sub/project" "$HOME/blocked-link"; do
        # This grant reopens the outer block, but not the inner one.
        run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/store/sub/project" \
          --block "$HOME" --block "$block" --allow-ro "$HOME/store" --allow-ro "$HOME/project" -- true
        [ "$status" -eq 1 ]
        [[ "$output" == *"custom block covers the project directory:"* ]]
      done
      for grant in "$HOME/store" "$HOME/store/sub" "$HOME/store/sub/project"; do
        run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/store/sub/project" \
          --block "$HOME/store" --allow-ro "$grant" -- true
        [ "$status" -eq 0 ]
      done
      run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/store/sub/project" \
        --block "$HOME" --block "$HOME/blocked-link" --allow-ro "$HOME/store/sub/project" -- true
      [ "$status" -eq 0 ]
    done
  done
}

@test "allow-ro: log header usage documents the read-only grant global" {
  local usage
  usage="$(sed -n '/^# Usage: write_log_header_json /,/^write_log_header_json()/p' "$SCODE_SOURCE")"
  [[ "$usage" == *'ALL_ALLOWED_RO[]'* ]]
}

@test "allow-ro: missing CLI and config paths are refused on both backends" {
  ro_fixture
  local platform mode
  for platform in darwin linux; do
    for mode in '' --strict; do
      run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/project" --allow-ro ../missing -- true
      [ "$status" -eq 1 ]
      [[ "$output" == *"read-only allowed path does not exist:"* ]]
      printf 'allowed_ro:\n  - ../missing\n' > "$SCODE_CONFIG"
      run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/project" -- true
      [ "$status" -eq 1 ]
      [[ "$output" == *"read-only allowed path does not exist:"* ]]
      : > "$SCODE_CONFIG"
      [ ! -e "$HOME/missing" ]
    done
  done
}

@test "allow-ro: both backends re-deny nested built-in and linked custom blocks" {
  ro_fixture
  mkdir -p "$HOME/.ssh" "$HOME/store/private"
  ln -s "$HOME/store/private" "$HOME/project/blocked-link"
  local platform mode tail canonical_home
  canonical_home="$(cd "$HOME" && pwd -P)"
  for platform in darwin linux; do
    for mode in '' --strict; do
      run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run $mode -C "$HOME/project" \
        --block "$HOME/project/blocked-link" --allow-ro "$HOME" -- true
      [ "$status" -eq 0 ]
      if [[ "$platform" == darwin ]]; then
        tail="${output##*; Explicit read-only grant}"
        [[ "$tail" == *'(deny file-read* file-write* process-exec'*"(subpath \"$canonical_home/.ssh\")"* ]]
        [[ "$tail" == *'(deny file-read* file-write* process-exec'*"(subpath \"$canonical_home/store/private\")"* ]]
      else
        tail="${output##*--ro-bind $canonical_home $canonical_home}"
        [[ "$tail" == *"--tmpfs $canonical_home/.ssh"* ]]
        [[ "$tail" == *"--tmpfs $canonical_home/store/private"* ]]
      fi
    done
  done
}

@test "allow-ro runtime: broad grants preserve nested blocks and narrow exceptions" {
  require_any_runtime_sandbox
  ro_fixture
  mkdir -p "$HOME/.ssh/deeper" "$HOME/store/private"
  printf secret > "$HOME/.ssh/secret"
  printf deeper > "$HOME/.ssh/deeper/secret"
  printf private > "$HOME/store/private/secret"
  ln -s "$HOME/store/private" "$HOME/project/blocked-link"
  local mode source
  for mode in '' --strict; do
    for source in cli config; do
      local -a flags=()
      if [[ "$source" == cli ]]; then
        flags=(--allow-ro "$HOME")
      else
        printf 'allowed_ro:\n  - "%s"\n' "$HOME" > "$SCODE_CONFIG"
      fi
      # Project blocks can tighten a user-config grant without discarding it.
      printf 'blocked:\n  - ./blocked-link\n  - ../.ssh/deeper\n' > "$HOME/project/.scode.yaml"
      run "$SCODE" $mode -C "$HOME/project" "${flags[@]}" -- /bin/sh -c \
        'cat "$1/store/sub/data" && ! cat "$1/.ssh/secret" && ! cat "$1/store/private/secret" && ! touch "$1/new"' sh "$HOME"
      echo "$output"
      [ "$status" -eq 0 ]
      # Deliberately give the child first: grant order must not change policy.
      run "$SCODE" $mode -C "$HOME/project" --allow-ro "$HOME/.ssh" "${flags[@]}" -- /bin/sh -c \
        'cat "$1/.ssh/secret" && ! cat "$1/.ssh/deeper/secret" && ! cat "$1/store/private/secret" && ! touch "$1/.ssh/new"' sh "$HOME"
      echo "$output"
      [ "$status" -eq 0 ]
      : > "$SCODE_CONFIG"
    done
  done
}

@test "allow-ro: log headers and audit record CLI and config read-only grants" {
  require_any_runtime_sandbox
  require_node
  ro_fixture
  printf 'allowed_ro:\n  - ../store/sub/data\n' > "$SCODE_CONFIG"
  local log_file="$TEST_PROJECT/readonly.log" canonical_store
  canonical_store="$(cd "$HOME/store" && pwd -P)"
  run "$SCODE" -C "$HOME/project" --allow-ro "$HOME/store/sub/tool" --log "$log_file" -- true
  [ "$status" -eq 0 ]
  run node -e '
    const fs = require("node:fs"), assert = require("node:assert/strict");
    const text = fs.readFileSync(process.argv[1], "utf8");
    const d = JSON.parse(text.split("\n")[0].slice(6));
    const paths = [process.argv[2] + "/sub/tool", process.argv[2] + "/sub/data"];
    assert.deepEqual(d.allowed_ro, paths);
    for (const path of paths) assert(text.includes("# allowed_ro: " + path + "\n"));
  ' "$log_file" "$canonical_store"
  [ "$status" -eq 0 ]
  printf '# blocked: default /store\n# allowed_ro: /store/child/\n#---\ndeny(file-read-data) /store/child/file\n' > "$log_file"
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not covered by scode defaults"* ]]
  [[ "$output" != *"Blocked by scode defaults:"* ]]
  printf '# blocked: default /store/child\n# allowed_ro: /store\n#---\ndeny(file-read-data) /store/child/file\n' > "$log_file"
  run "$SCODE" audit "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Blocked by scode defaults:"* ]]
}

@test "allow-ro: supported configuration format lists every path section" {
  local section format
  format="$(sed -n '/^## Supported format/,/^## File acceptance/p' "$BATS_TEST_DIRNAME/../docs/configuration.md")"
  for section in blocked allowed allowed_ro; do
    [[ "$format" == *"\`$section:\`"* ]]
  done
}

@test "allow-ro: Linux project restoration preserves custom blocks and read-only caps" {
  ro_fixture
  mkdir -p "$HOME/Documents/project" "$HOME/Documents/project/private"
  local home mode tail
  home="$(cd "$HOME" && pwd -P)"
  for mode in '' --strict; do
    run env _SCODE_PLATFORM=linux "$SCODE" --dry-run $mode -C "$HOME/Documents/project" \
      --allow-ro "$HOME" --block "$HOME/Documents/project/private" -- true
    [ "$status" -eq 0 ]
    tail="${output##*--ro-bind $home $home}"
    [[ "$tail" == *"--tmpfs $home/Documents"*"--ro-bind $home/Documents/project $home/Documents/project"*"--tmpfs $home/Documents/project/private"* ]]
    run env _SCODE_PLATFORM=linux "$SCODE" --dry-run $mode -C "$HOME/Documents/project" \
      --allow-ro "$HOME" --block "$HOME/Documents/project" -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"custom block covers the project directory:"* ]]
  done
}

@test "allow-ro runtime: command auto-allow remains exact after nested blocks" {
  require_any_runtime_sandbox
  ro_fixture
  mkdir "$HOME/.ssh"
  printf secret > "$HOME/.ssh/secret"
  printf '#!/bin/sh\n! cat "$HOME/.ssh/secret" && ! echo changed > "$0"\n' > "$HOME/.ssh/tool"
  chmod +x "$HOME/.ssh/tool"
  local mode
  for mode in '' --strict; do
    run "$SCODE" $mode -C "$HOME/project" --allow-ro "$HOME" -- "$HOME/.ssh/tool"
    echo "$output"
    [ "$status" -eq 0 ]
  done
}

@test "allow-ro: strict nested child grants retain metadata and Linux mount ordering" {
  ro_fixture
  mkdir -p "$HOME/.ssh/child" "$HOME/store/private/child"
  local platform block root tail canonical_home
  canonical_home="$(cd "$HOME" && pwd -P)"
  for platform in darwin linux; do
    for block in "$canonical_home/.ssh" "$canonical_home/store/private"; do
      local -a flags=()
      root="$canonical_home"
      if [[ "$block" == */store/private ]]; then
        flags=(--block "$block")
        root="$canonical_home/store"
      fi
      run env _SCODE_PLATFORM="$platform" "$SCODE" --dry-run --strict -C "$HOME/project" \
        "${flags[@]}" --allow-ro "$root" --allow "$block/child" -- /usr/bin/stat "$block"
      [ "$status" -eq 0 ]
      if [[ "$platform" == darwin ]]; then
        # The exact metadata operation survives the later file-read* deny;
        # the runtime test below checks Seatbelt, not a last-rule-wins model.
        [[ "$output" == *"(allow file-read-metadata (literal \"$block\"))"*'; Explicit read-only grant'* ]]
        tail="${output##*; Explicit read-only grant}"
        [[ "$tail" == *'(deny file-write*'*'(deny file-read* file-write* process-exec'*"(subpath \"$block\")"*"(require-not (subpath \"$block/child\"))"* ]]
      else
        # Reopen the child after masking the parent exposed by the RO bind.
        tail="${output##*--ro-bind $root $root}"
        [[ "$tail" == *"--tmpfs $block"*"--ro-bind $block/child $block/child"* ]]
        tail="${tail##*--ro-bind $block/child $block/child}"
        [[ "$tail" != *"--tmpfs $block"* ]]
        [[ "$tail" != *"--ro-bind $root $root"* ]]
      fi
    done
  done
}

@test "allow-ro runtime: strict nested child grants keep every prefix stat-reachable" {
  require_any_runtime_sandbox
  ro_fixture
  mkdir -p "$HOME/.ssh/child" "$HOME/store/private/child"
  local block root mode
  for block in "$HOME/.ssh" "$HOME/store/private"; do
    printf child-data > "$block/child/data"
    printf sibling-secret > "$block/secret"
    local -a flags=()
    root="$HOME"
    if [[ "$block" == */store/private ]]; then
      flags=(--block "$block")
      root="$HOME/store"
    fi
    for mode in baseline read-only; do
      local -a ro_flags=()
      [[ "$mode" == read-only ]] && ro_flags=(--allow-ro "$root")
      run "$SCODE" --strict -C "$HOME/project" "${flags[@]}" \
        --allow "$block/child" "${ro_flags[@]}" -- /bin/sh -c '
          path="$1/child"
          while :; do
            /usr/bin/stat "$path" >/dev/null || exit 1
            [ "$path" = / ] && break
            path="$(dirname "$path")"
          done
          [ "$(cat "$1/child/data")" = child-data ] || exit 2
          if cat "$1/secret"; then exit 3; fi
          if [ "$2" = read-only ]; then
            if printf changed > "$1/child/data"; then exit 4; fi
            if touch "$1/child/new"; then exit 5; fi
          fi
          echo prefixes-and-policy-ok
        ' sh "$block" "$mode"
      echo "$output"
      [ "$status" -eq 0 ]
      [[ "$output" == *prefixes-and-policy-ok* ]]
    done
  done
}
