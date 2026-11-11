#!/usr/bin/env bats
# Built-in blocks under --strict.
#
# Strict mode denies by default, and through v0.6.5 it emitted no rule for a
# built-in block at all. A grant that covered one reopened it: with the
# project at HOME (`scode --strict -C ~`), ~/.ssh lay inside the project
# grant and was readable. Every fixture lives in a HOME under the test's
# temporary directory; the real home is never read or written.

load test_helper

# Fixture home: credentials, a linked block resolving into a work tree, and
# a project source file.
setup_strict_home() {
  SHOME="$TEST_PROJECT/home"
  mkdir -p "$SHOME/.ssh" "$SHOME/.config/gh" "$SHOME/work/aws" "$SHOME/work/src" \
    "$SHOME/Library/Preferences"
  printf 'ssh-fixture-value\n' > "$SHOME/.ssh/id_fixture"
  printf 'known-hosts-fixture\n' > "$SHOME/.ssh/known_hosts"
  printf 'gh-fixture-value\n' > "$SHOME/.config/gh/hosts.yml"
  printf 'aws-fixture-value\n' > "$SHOME/work/aws/credentials"
  printf 'library-fixture-value\n' > "$SHOME/Library/Preferences/fixture.plist"
  printf 'source-fixture-value\n' > "$SHOME/work/src/main.c"
  ln -s "${1:-work/aws}" "$SHOME/.aws"
  SHOME_REAL="$(cd -P "$SHOME" && pwd -P)"
  # Config normally comes from the account home even with a fixture HOME.
  # Select an empty fixture explicitly so operator policy is never read.
  export SCODE_CONFIG="$SHOME/sandbox.yaml"
  : > "$SCODE_CONFIG"
}

strict_dry_run() {
  local platform="$1" project="$2"
  shift 2
  run env HOME="$SHOME" _SCODE_PLATFORM="$platform" \
    "$SCODE" --dry-run --strict -C "$project" "$@"
}

# Line number of the last line equal to $2 in $1 (0 when absent).
last_line_of() {
  printf '%s\n' "$1" | awk -v want="$2" '$0 == want { n = NR } END { print n + 0 }'
}

# Line number of the last bwrap word equal to the words in $2 (0 when absent).
last_bwrap_index() {
  local args
  args="$(printf '%s\n' "$1" | grep -m1 '^bwrap ')"
  printf '%s\n' "$args" | awk -v want="$2" '
    { n = split($0, w, " "); k = split(want, x, " ")
      for (i = 1; i <= n - k + 1; i++) {
        ok = 1
        for (j = 1; j <= k; j++) if (w[i + j - 1] != x[j]) { ok = 0; break }
        if (ok) last = i
      } }
    END { print last + 0 }'
}

subpath_line() {
  printf '  (subpath "%s")' "$1"
}

# ---------- Dry-run profile (macOS rendering, any host) ----------

@test "strict macOS: a project at HOME denies built-in blocks after the project grant" {
  setup_strict_home
  strict_dry_run darwin "$SHOME" -- true
  [ "$status" -eq 0 ]
  local grant_line line block
  grant_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL")")"
  [ "$grant_line" -gt 0 ]
  for block in .ssh .config/gh .gnupg Library .zsh_history; do
    line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/$block")")"
    [ "$line" -gt "$grant_line" ]
  done
  [[ "$output" == *"; Built-in blocks inside granted paths"* ]]
}

@test "strict macOS: a linked block resolving into the project is denied at every spelling" {
  setup_strict_home
  strict_dry_run darwin "$SHOME/work" -- true
  [ "$status" -eq 0 ]
  local rule
  rule="(deny file-read* file-write* process-exec"$'\n'"$(subpath_line "$SHOME_REAL/.aws")"
  rule+=$'\n'"$(subpath_line "$SHOME_REAL/work/aws")"$'\n'")"
  [[ "$output" == *"; Built-in blocks inside granted paths"$'\n'"$rule"* ]]
  # Built-in blocks outside every grant need no rule under deny-default.
  [[ "$output" != *"$(subpath_line "$SHOME_REAL/.ssh")"* ]]
}

@test "strict macOS: no built-in rule is emitted when no grant covers a block" {
  setup_strict_home
  mkdir -p "$TEST_PROJECT/elsewhere"
  strict_dry_run darwin "$TEST_PROJECT/elsewhere" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"; Built-in blocks inside granted paths"* ]]
}

@test "strict macOS: an explicit --allow of a built-in block lifts it inside the project" {
  setup_strict_home
  strict_dry_run darwin "$SHOME" --allow "$SHOME/.ssh" -- true
  [ "$status" -eq 0 ]
  local grant_line deny_line
  grant_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.ssh")")"
  [ "$grant_line" -gt 0 ]
  # The only rule naming ~/.ssh is the allow itself.
  [[ "$(printf '%s\n' "$output" | grep -c "(subpath \"$SHOME_REAL/.ssh\")")" -eq 1 ]]
  deny_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.config/gh")")"
  [ "$deny_line" -gt 0 ]
}

@test "strict macOS: an allowed child of a built-in block in the project is granted after the deny" {
  setup_strict_home
  strict_dry_run darwin "$SHOME" --allow "$SHOME/.ssh/known_hosts" -- true
  [ "$status" -eq 0 ]
  local deny_line allow_line
  deny_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.ssh")")"
  allow_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.ssh/known_hosts")")"
  [ "$deny_line" -gt 0 ]
  [ "$allow_line" -gt "$deny_line" ]
}

@test "strict macOS: a link from a built-in block into harness state is denied after the grant" {
  setup_strict_home .codex/aws
  mkdir -p "$SHOME/.codex/aws"
  mkdir -p "$TEST_PROJECT/elsewhere"
  strict_dry_run darwin "$TEST_PROJECT/elsewhere" -- codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+codex: auto-allowing"* ]]
  local grant_line deny_line
  grant_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.codex")")"
  deny_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.codex/aws")")"
  [ "$grant_line" -gt 0 ]
  [ "$deny_line" -gt "$grant_line" ]
}

@test "strict macOS: a project that is a built-in block is granted, not denied" {
  setup_strict_home
  strict_dry_run darwin "$SHOME/.ssh" -- true
  [ "$status" -eq 0 ]
  local grant_line
  grant_line="$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.ssh")")"
  [ "$grant_line" -gt 0 ]
  [[ "$(printf '%s\n' "$output" | sed -n "$((grant_line - 1))p")" == "(allow file-read* file-write*" ]]
  [[ "$output" != *"; Built-in blocks inside granted paths"* ]]
}

@test "strict: a custom block covering the project is still refused" {
  setup_strict_home
  strict_dry_run darwin "$SHOME/work" --block "$SHOME" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom block covers the project directory"* ]]
  strict_dry_run linux "$SHOME/work" --block "$SHOME" -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom block covers the project directory"* ]]
}

# ---------- Dry-run arguments (Linux rendering, any host) ----------

@test "strict Linux: a project at HOME masks built-in blocks after the project bind" {
  setup_strict_home
  strict_dry_run linux "$SHOME" -- true
  [ "$status" -eq 0 ]
  local bind_i i block
  bind_i="$(last_bwrap_index "$output" "--bind $SHOME_REAL $SHOME_REAL")"
  [ "$bind_i" -gt 0 ]
  for block in .ssh .config/gh .gnupg; do
    i="$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/$block")"
    [ "$i" -gt "$bind_i" ]
  done
}

@test "strict Linux: a linked block resolving into the project is masked at its target" {
  setup_strict_home
  strict_dry_run linux "$SHOME/work" -- true
  [ "$status" -eq 0 ]
  local bind_i i
  bind_i="$(last_bwrap_index "$output" "--bind $SHOME_REAL/work $SHOME_REAL/work")"
  i="$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/work/aws")"
  [ "$bind_i" -gt 0 ]
  [ "$i" -gt "$bind_i" ]
  # Nothing outside a bound tree needs a mask.
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.ssh")" -eq 0 ]
}

@test "strict Linux: an explicit --allow of a built-in block lifts it inside the project" {
  setup_strict_home
  strict_dry_run linux "$SHOME" --allow "$SHOME/.ssh" -- true
  [ "$status" -eq 0 ]
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.ssh")" -eq 0 ]
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.config/gh")" -gt 0 ]
}

@test "strict Linux: an allowed child of a built-in block in the project is bound after the mask" {
  setup_strict_home
  strict_dry_run linux "$SHOME" --allow "$SHOME/.ssh/known_hosts" -- true
  [ "$status" -eq 0 ]
  local mask_i bind_i
  mask_i="$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.ssh")"
  bind_i="$(last_bwrap_index "$output" "--bind $SHOME_REAL/.ssh/known_hosts $SHOME_REAL/.ssh/known_hosts")"
  [ "$mask_i" -gt 0 ]
  [ "$bind_i" -gt "$mask_i" ]
}

@test "strict Linux: a project that is a built-in block is bound, not masked" {
  setup_strict_home
  strict_dry_run linux "$SHOME/.ssh" -- true
  [ "$status" -eq 0 ]
  [ "$(last_bwrap_index "$output" "--bind $SHOME_REAL/.ssh $SHOME_REAL/.ssh")" -gt 0 ]
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.ssh")" -eq 0 ]
}

@test "strict Linux: blocks inside harness state are masked after its bind" {
  setup_strict_home .codex/aws
  mkdir -p "$SHOME/.codex/aws" "$SHOME/.codex/private"
  mkdir -p "$TEST_PROJECT/elsewhere"
  strict_dry_run linux "$TEST_PROJECT/elsewhere" --block "$SHOME/.codex/private" -- codex
  [ "$status" -eq 0 ]
  local bind_i
  bind_i="$(last_bwrap_index "$output" "--bind $SHOME_REAL/.codex $SHOME_REAL/.codex")"
  [ "$bind_i" -gt 0 ]
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.codex/aws")" -gt "$bind_i" ]
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.codex/private")" -gt "$bind_i" ]
}

@test "strict Linux: read-only project binds precede built-in masks and child exceptions" {
  setup_strict_home
  strict_dry_run linux "$SHOME" --ro --allow "$SHOME/.ssh/known_hosts" -- true
  [ "$status" -eq 0 ]
  local project_i mask_i child_i
  project_i="$(last_bwrap_index "$output" "--ro-bind $SHOME_REAL $SHOME_REAL")"
  mask_i="$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.ssh")"
  child_i="$(last_bwrap_index "$output" "--ro-bind $SHOME_REAL/.ssh/known_hosts $SHOME_REAL/.ssh/known_hosts")"
  [ "$project_i" -gt 0 ]
  [ "$mask_i" -gt "$project_i" ]
  [ "$child_i" -gt "$mask_i" ]
}

@test "strict macOS: automatic harness state cannot reopen a built-in parent" {
  setup_strict_home
  mkdir -p "$SHOME/.ssh/state"
  ln -s .ssh/state "$SHOME/.codex"
  mkdir -p "$TEST_PROJECT/elsewhere"
  strict_dry_run darwin "$TEST_PROJECT/elsewhere" -- codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"built-in block prevents automatic state grant"* ]]
  [ "$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.ssh/state")")" -eq 0 ]
}

@test "strict Linux: automatic harness state cannot reopen a built-in parent" {
  setup_strict_home
  mkdir -p "$SHOME/.ssh/state"
  ln -s .ssh/state "$SHOME/.codex"
  mkdir -p "$TEST_PROJECT/elsewhere"
  strict_dry_run linux "$TEST_PROJECT/elsewhere" -- codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"built-in block prevents automatic state grant"* ]]
  [ "$(last_bwrap_index "$output" "--bind $SHOME_REAL/.ssh/state $SHOME_REAL/.ssh/state")" -eq 0 ]
}

@test "strict: link names, targets, and ancestors lift a built-in block on both platforms" {
  setup_strict_home
  local platform allowed
  for platform in darwin linux; do
    for allowed in "$SHOME/.aws" "$SHOME/work/aws" "$SHOME/work"; do
      strict_dry_run "$platform" "$SHOME" --allow "$allowed" -- true
      [ "$status" -eq 0 ]
      if [[ "$platform" == darwin ]]; then
        [[ "$output" != *"$(subpath_line "$SHOME_REAL/.aws")"* ]]
      else
        [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/work/aws")" -eq 0 ]
      fi
    done
  done
}

@test "strict: a custom block resolving onto the project is refused on both platforms" {
  setup_strict_home
  ln -s work "$SHOME/project-link"
  local platform
  for platform in darwin linux; do
    strict_dry_run "$platform" "$SHOME/work" --block "$SHOME/project-link" -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"custom block covers the project directory"* ]]
    strict_dry_run "$platform" "$SHOME/work" --block "$SHOME/project-link" --allow "$SHOME/work" -- true
    [ "$status" -eq 0 ]
  done
}

@test "strict: a linked file block and an intermediate link remain blocked" {
  setup_strict_home
  printf 'npm-fixture-value\n' > "$SHOME/work/npmrc"
  ln -s work/npmrc "$SHOME/npm-link"
  ln -s npm-link "$SHOME/.npmrc"
  strict_dry_run darwin "$SHOME/work" -- true
  [ "$status" -eq 0 ]
  local rule
  rule="(deny file-read* file-write* process-exec"$'\n'"$(subpath_line "$SHOME_REAL/.npmrc")"
  rule+=$'\n'"$(subpath_line "$SHOME_REAL/npm-link")"$'\n'"$(subpath_line "$SHOME_REAL/work/npmrc")"$'\n'")"
  [[ "$output" == *"$rule"* ]]
  strict_dry_run linux "$SHOME/work" -- true
  [ "$status" -eq 0 ]
  [ "$(last_bwrap_index "$output" "--ro-bind /dev/null $SHOME_REAL/work/npmrc")" -gt \
    "$(last_bwrap_index "$output" "--bind $SHOME_REAL/work $SHOME_REAL/work")" ]
}

@test "strict: explicit allows can reopen blocked automatic state" {
  setup_strict_home
  mkdir -p "$SHOME/.ssh/state"
  ln -s .ssh/state "$SHOME/.codex"
  local platform
  for platform in darwin linux; do
    strict_dry_run "$platform" "$SHOME" --allow "$SHOME/.ssh" -- codex
    [ "$status" -eq 0 ]
    [[ "$output" != *"built-in block prevents automatic state grant"* ]]
    if [[ "$platform" == darwin ]]; then
      [ "$(last_line_of "$output" "$(subpath_line "$SHOME_REAL/.ssh/state")")" -gt 0 ]
    else
      [ "$(last_bwrap_index "$output" "--bind $SHOME_REAL/.ssh/state $SHOME_REAL/.ssh/state")" -gt 0 ]
    fi
  done
}

@test "strict: a built-in link into a system read grant is still blocked" {
  setup_strict_home
  ln -s /usr/bin/false "$SHOME/.npmrc"
  strict_dry_run darwin "$SHOME/work" -- /bin/sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(subpath_line /usr/bin/false)"* ]]
  strict_dry_run linux "$SHOME/work" -- /bin/sh
  [ "$status" -eq 0 ]
  [ "$(last_bwrap_index "$output" '--ro-bind /dev/null /usr/bin/false')" -gt 0 ]
}

@test "Linux: read-only projects retain built-in masks in default mode too" {
  setup_strict_home
  run env HOME="$SHOME" _SCODE_PLATFORM=linux "$SCODE" --dry-run --ro -C "$SHOME" -- true
  [ "$status" -eq 0 ]
  [ "$(last_bwrap_index "$output" "--tmpfs $SHOME_REAL/.ssh")" -gt \
    "$(last_bwrap_index "$output" "--ro-bind $SHOME_REAL $SHOME_REAL")" ]
}

# ---------- Runtime (sandbox-exec) ----------

@test "strict macOS runtime: built-in blocks inside the project are unreadable" {
  require_runtime_sandbox
  setup_strict_home
  # The script prints a count and the source file; the fixture values live
  # only in the files, never in the command text.
  HOME="$SHOME" run "$SCODE" --strict --no-net -C "$SHOME" -- /bin/sh -c '
    n=0
    for f in "$@"; do cat "$f" 2>/dev/null && n=$((n + 1)); done
    echo "count=$n"
    cat work/src/main.c
  ' sh .ssh/id_fixture .config/gh/hosts.yml .aws/credentials work/aws/credentials \
    Library/Preferences/fixture.plist
  [ "$status" -eq 0 ]
  [[ "$output" == *"count=0"* ]]
  [[ "$output" != *"fixture-value"*"count="* ]]
  [[ "$output" == *"source-fixture-value"* ]]
}

@test "strict macOS runtime: an explicit --allow lifts one built-in block only" {
  require_runtime_sandbox
  setup_strict_home
  HOME="$SHOME" run "$SCODE" --strict --no-net -C "$SHOME" --allow "$SHOME/.ssh" -- /bin/sh -c '
    cat .ssh/id_fixture
    n=0
    cat .config/gh/hosts.yml 2>/dev/null && n=$((n + 1))
    echo "count=$n"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh-fixture-value"* ]]
  [[ "$output" == *"count=0"* ]]
  [[ "$output" != *"gh-fixture-value"* ]]
}

@test "strict macOS runtime: a read-only HOME preserves blocks and child allows" {
  require_runtime_sandbox
  setup_strict_home
  HOME="$SHOME" run "$SCODE" --strict --no-net --ro -C "$SHOME" \
    --allow "$SHOME/.ssh/known_hosts" -- /bin/sh -c '
    cat .ssh/known_hosts
    cat .ssh/id_fixture 2>/dev/null && exit 1
    cat .aws/credentials 2>/dev/null && exit 1
    (echo changed > work/src/main.c) 2>/dev/null && exit 1
    cat work/src/main.c
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"known-hosts-fixture"* ]]
  [[ "$output" == *"source-fixture-value"* ]]
  [[ "$output" != *"ssh-fixture-value"* && "$output" != *"aws-fixture-value"* ]]
}

@test "strict Linux runtime: read-only HOME preserves masks and child allows" {
  require_linux_bwrap
  setup_strict_home
  HOME="$SHOME" run "$SCODE" --strict --no-net --ro -C "$SHOME" \
    --allow "$SHOME/.ssh/known_hosts" -- /bin/sh -c '
    cat .ssh/known_hosts
    cat .ssh/id_fixture 2>/dev/null && exit 1
    cat .aws/credentials 2>/dev/null && exit 1
    (echo changed > work/src/main.c) 2>/dev/null && exit 1
    cat work/src/main.c
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"known-hosts-fixture"* ]]
  [[ "$output" == *"source-fixture-value"* ]]
  [[ "$output" != *"ssh-fixture-value"* && "$output" != *"aws-fixture-value"* ]]
}
