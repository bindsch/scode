#!/usr/bin/env bats
# Project precedence under built-in parents and automatic harness state.
load test_helper

setup_precedence_home() {
  PHOME="$TEST_PROJECT/home"
  mkdir -p "$PHOME/Documents/work/project/private" "$PHOME/.codex/aws/project/private"
  PHOME="$(cd -P "$PHOME" && pwd -P)"
  export SCODE_CONFIG="$PHOME/empty.yaml"
  : > "$SCODE_CONFIG"
  ln -s .codex/aws "$PHOME/.aws"
  ln -s Documents/work/project/private "$PHOME/.ssh"
  printf 'project-source\n' > "$PHOME/Documents/work/project/source"
  printf 'blocked-fixture\n' > "$PHOME/Documents/work/project/private/secret"
  printf 'project-source\n' > "$PHOME/.codex/aws/source"
  printf 'project-source\n' > "$PHOME/.codex/aws/project/source"
  printf 'blocked-fixture\n' > "$PHOME/.codex/aws/project/private/secret"
}

last_mount() {
  printf '%s\n' "$output" | awk -v want="$1" '
    /^bwrap / { n = split($0, a, " "); k = split(want, b, " ")
      for (i = 1; i <= n-k+1; i++) {
        match_all = 1
        for (j = 1; j <= k; j++) if (a[i+j-1] != b[j]) match_all = 0
        if (match_all) last = i
      }
    } END { print last+0 }'
}

require_precedence_runtime() {
  if [[ "$(uname -s)" == Linux ]]; then
    require_linux_bwrap
  else
    require_runtime_sandbox
  fi
}

@test "Linux: restored allowed ancestors cannot override a read-only project" {
  setup_precedence_home
  local mode project="$PHOME/Documents/work/project" parent="$PHOME/Documents/work"
  for mode in '' --strict; do
    run env HOME="$PHOME" _SCODE_PLATFORM=linux "$SCODE" --dry-run ${mode:+"$mode"} --ro \
      -C "$project" --allow "$parent" -- true
    [ "$status" -eq 0 ]
    [ "$(last_mount "--ro-bind $project $project")" -gt "$(last_mount "--bind $parent $parent")" ]
  done
}

@test "macOS: final write denial follows ancestor grants" {
  setup_precedence_home
  local mode project="$PHOME/Documents/work/project" parent="$PHOME/Documents/work"
  for mode in '' --strict; do
    run env HOME="$PHOME" _SCODE_PLATFORM=darwin "$SCODE" --dry-run ${mode:+"$mode"} --ro \
      -C "$project" --allow "$parent" -- true
    [ "$status" -eq 0 ]
    [[ "$output" == *"; Final read-only project invariant"$'\n'"(deny file-write*"$'\n'"  (subpath \"$project\")"* ]]
    local tail="${output##*; Final read-only project invariant}"
    [[ "$tail" != *"(allow file-read* file-write*"* ]]
  done
}

@test "strict Linux: automatic state cannot mask a project equal to or inside a built-in block" {
  setup_precedence_home
  local project
  for project in "$PHOME/.codex/aws" "$PHOME/.codex/aws/project"; do
    run env HOME="$PHOME" _SCODE_PLATFORM=linux "$SCODE" --dry-run --strict \
      -C "$project" --block "$PHOME/.codex/aws/project/private" -- codex
    [ "$status" -eq 0 ]
    [ "$(last_mount "--bind $PHOME/.codex $PHOME/.codex")" -gt 0 ]
    if [[ "$project" == "$PHOME/.codex/aws" ]]; then
      [ "$(last_mount "--tmpfs $PHOME/.codex/aws")" -eq 0 ]
    else
      [ "$(last_mount "--tmpfs $PHOME/.codex/aws")" -gt 0 ]
      [ "$(last_mount "--bind $project $project")" -gt "$(last_mount "--tmpfs $PHOME/.codex/aws")" ]
    fi
    [ "$(last_mount "--tmpfs $PHOME/.codex/aws/project/private")" -gt 0 ]
  done
}

@test "runtime: a project under a linked built-in block never exposes sibling credentials" {
  require_precedence_runtime
  setup_precedence_home
  mkdir -p "$PHOME/bin"
  printf 'private-credential\n' > "$PHOME/.codex/aws/credentials"
  printf 'allowed-sibling\n' > "$PHOME/.codex/aws/allowed.txt"
  cat > "$PHOME/bin/codex" <<'SH'
#!/bin/sh
cat source || exit 11
cat private/secret 2>/dev/null && exit 12
cat "$HOME/.codex/aws/credentials" 2>/dev/null && exit 13
cat "$HOME/.aws/credentials" 2>/dev/null && exit 14
cat "$HOME/.codex/aws/allowed.txt" || exit 15
echo writable >> "$HOME/.codex/aws/allowed.txt" || exit 16
if [ "$1" = --ro ]; then
  (echo changed > source) 2>/dev/null && exit 17
else
  echo project-source > source || exit 18
fi
exit 0
SH
  chmod +x "$PHOME/bin/codex"
  local mode access
  for mode in '' --strict; do
    for access in --rw --ro; do
      HOME="$PHOME" run "$SCODE" ${mode:+"$mode"} "$access" --no-net \
        -C "$PHOME/.codex/aws/project" --block "$PHOME/.codex/aws/project/private" \
        --allow "$PHOME/.codex/aws/allowed.txt" -- "$PHOME/bin/codex" "$access"
      echo "$output"
      [ "$status" -eq 0 ]
      [[ "$output" == *project-source*allowed-sibling* ]]
      [[ "$output" != *private-credential* ]]
    done
  done
}

@test "runtime: a built-in parent mask preserves allowed project ancestors and read-only" {
  require_precedence_runtime
  setup_precedence_home
  mkdir -p "$PHOME/bin" "$PHOME/.codex/aws/work/project"
  printf 'project-source\n' > "$PHOME/.codex/aws/work/project/source"
  printf 'private-credential\n' > "$PHOME/.codex/aws/credentials"
  cat > "$PHOME/bin/codex" <<'SH'
#!/bin/sh
cat source || exit 11
cat "$HOME/.codex/aws/credentials" 2>/dev/null && exit 13
echo allowed-sibling > ../sibling || exit 14
if [ "$1" = --ro ]; then
  (echo changed > source) 2>/dev/null && exit 15
else
  echo project-source > source || exit 16
fi
exit 0
SH
  chmod +x "$PHOME/bin/codex"
  local access
  for access in --rw --ro; do
    HOME="$PHOME" run "$SCODE" --strict "$access" --no-net \
      -C "$PHOME/.codex/aws/work/project" --allow "$PHOME/.codex/aws/work" \
      -- "$PHOME/bin/codex" "$access"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *project-source* ]]
    [[ "$output" != *private-credential* ]]
  done
}

@test "strict macOS: automatic state cannot deny a project equal to or inside a built-in block" {
  setup_precedence_home
  local project
  for project in "$PHOME/.codex/aws" "$PHOME/.codex/aws/project"; do
    run env HOME="$PHOME" _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict \
      -C "$project" --block "$PHOME/.codex/aws/project/private" -- codex
    [ "$status" -eq 0 ]
    [[ "$output" == *"strict+codex: auto-allowing"* ]]
    [[ "$output" != *"(deny file-read* file-write* process-exec"$'\n'"  (subpath \"$PHOME/.aws\")"* ]]
    [[ "$output" == *"(deny file-read* file-write* process-exec"$'\n'"  (subpath \"$PHOME/.codex/aws/project/private\")"* ]]
  done
}

@test "runtime: allowed ancestor preserves project read-only" {
  require_precedence_runtime
  setup_precedence_home
  local mode project="$PHOME/Documents/work/project" parent="$PHOME/Documents/work"
  for mode in '' --strict; do
    HOME="$PHOME" run "$SCODE" ${mode:+"$mode"} --no-net --ro -C "$project" --allow "$parent" -- /bin/sh -c '
      (echo changed > source) 2>/dev/null && exit 11
      echo sibling-write > ../sibling || exit 13
      cat source
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"project-source"* ]]
  done
}

@test "runtime: automatic state preserves projects equal to and inside built-in blocks" {
  require_precedence_runtime
  setup_precedence_home
  # Only this synthetic executable is run; no installed harness is invoked.
  mkdir -p "$PHOME/bin"
  cat > "$PHOME/bin/codex" <<'SH'
#!/bin/sh
cat source || exit 11
cat "$1" 2>/dev/null && exit 12
(echo changed > source) 2>/dev/null && exit 13
exit 0
SH
  chmod +x "$PHOME/bin/codex"
  local project
  for project in "$PHOME/.codex/aws" "$PHOME/.codex/aws/project"; do
    HOME="$PHOME" run "$SCODE" --strict --no-net --ro -C "$project" \
      --block "$PHOME/.codex/aws/project/private" -- "$PHOME/bin/codex" \
      "$PHOME/.codex/aws/project/private/secret"
    [ "$status" -eq 0 ]
    [[ "$output" == *"strict+codex: auto-allowing"* ]]
    [[ "$output" == *"project-source"* ]]
    [[ "$output" != *"blocked-fixture"* ]]
  done
}
