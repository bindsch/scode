#!/usr/bin/env bats
# macOS blocks whose path is a symbolic link, or runs through one.
#
# Seatbelt matches a rule against the path the kernel resolved. A rule on a
# link name alone left its target readable: with ~/.aws -> ~/dotfiles/aws,
# `cat ~/dotfiles/aws/credentials` printed the secret through v0.6.4. Every
# fixture lives in a HOME under the test's temporary directory; the real
# home is never read or written.

load test_helper

# Fixture home with a directory link, a file link, and a linked ancestor.
setup_link_home() {
  LINK_HOME="$TEST_PROJECT/home"
  mkdir -p "$LINK_HOME/dotfiles/aws" "$LINK_HOME/dotfiles/config/gh" \
    "$LINK_HOME/dotfiles/vim" "$LINK_HOME/work"
  printf 'aws-fixture-value\n' > "$LINK_HOME/dotfiles/aws/credentials"
  printf 'npm-fixture-value\n' > "$LINK_HOME/dotfiles/npmrc"
  printf 'gh-fixture-value\n' > "$LINK_HOME/dotfiles/config/gh/hosts.yml"
  printf 'sibling-fixture-value\n' > "$LINK_HOME/dotfiles/vim/vimrc"
  ln -s dotfiles/aws "$LINK_HOME/.aws"
  ln -s dotfiles/npmrc "$LINK_HOME/.npmrc"
  ln -s dotfiles/config "$LINK_HOME/.config"
  LINK_HOME_REAL="$(cd -P "$LINK_HOME" && pwd -P)"
}

link_darwin_dry_run() {
  run env HOME="$LINK_HOME" _SCODE_PLATFORM=darwin \
    "$SCODE" --dry-run -C "$LINK_HOME/work" "$@" -- true
}

# One deny rule naming exactly these spellings, in this order.
deny_rule() {
  local rule="(deny file-read* file-write* process-exec" spelling
  for spelling in "$@"; do
    rule+=$'\n'"  (subpath \"${spelling}\")"
  done
  printf '%s\n)' "$rule"
}

# Line number of the last line equal to $2 in $1 (0 when absent).
last_line_of() {
  printf '%s\n' "$1" | awk -v want="$2" '$0 == want { n = NR } END { print n + 0 }'
}

# ---------- Dry-run profile (macOS rendering, any host) ----------

@test "macOS links: a directory-link block denies its name and its target" {
  setup_link_home
  link_darwin_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.aws" "$LINK_HOME_REAL/dotfiles/aws")"* ]]
}

@test "macOS links: a file-link block denies its name and its target" {
  setup_link_home
  link_darwin_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.npmrc" "$LINK_HOME_REAL/dotfiles/npmrc")"* ]]
}

@test "macOS links: a block under a linked ancestor denies the resolved path" {
  setup_link_home
  link_darwin_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.config/gh" "$LINK_HOME_REAL/dotfiles/config/gh")"* ]]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.config/gcloud" "$LINK_HOME_REAL/dotfiles/config/gcloud")"* ]]
}

@test "macOS links: every intermediate link of a chain is denied" {
  setup_link_home
  # ~/.config -> ../home/links/config, and ~/links -> dotfiles: the second
  # link is reached only after "..", and each name on the way is denied.
  rm "$LINK_HOME/.config"
  ln -s ../home/links/config "$LINK_HOME/.config"
  ln -s dotfiles "$LINK_HOME/links"
  link_darwin_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.config/gh" \
    "$LINK_HOME_REAL/links/config/gh" "$LINK_HOME_REAL/dotfiles/config/gh")"* ]]
}

@test "macOS links: a dangling link is denied at the target its creation would use" {
  setup_link_home
  ln -s dotfiles/removed/ssh "$LINK_HOME/.ssh"
  link_darwin_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.ssh" "$LINK_HOME_REAL/dotfiles/removed/ssh")"* ]]
  # A missing path that is no link keeps its single rule.
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.kube")"* ]]
}

@test "macOS links: a link cycle still denies every name in it" {
  setup_link_home
  ln -s .gnupg-loop "$LINK_HOME/.gnupg"
  ln -s .gnupg "$LINK_HOME/.gnupg-loop"
  link_darwin_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(deny_rule "$LINK_HOME_REAL/.gnupg" "$LINK_HOME_REAL/.gnupg-loop")"* ]]
}

@test "macOS links: a --block on a link keeps the link name and the target" {
  setup_link_home
  mkdir -p "$LINK_HOME/notes"
  ln -s notes "$LINK_HOME/notes-link"
  link_darwin_dry_run --block "$LINK_HOME_REAL/notes-link"
  [ "$status" -eq 0 ]
  local rule
  rule="$(deny_rule "$LINK_HOME_REAL/notes-link" "$LINK_HOME_REAL/notes")"
  [[ "$output" == *"; Final custom-policy blocks"$'\n'"$rule"* ]]
}

@test "macOS links: strict mode denies every spelling of a linked custom block" {
  setup_link_home
  mkdir -p "$LINK_HOME/notes"
  ln -s notes "$LINK_HOME/notes-link"
  link_darwin_dry_run --strict --block "$LINK_HOME_REAL/notes-link"
  [ "$status" -eq 0 ]
  local rule
  rule="$(deny_rule "$LINK_HOME_REAL/notes-link" "$LINK_HOME_REAL/notes")"
  [[ "$output" == *"; Blocked directories"$'\n'"$rule"* ]]
  [[ "$output" == *"; Final custom-policy blocks"$'\n'"$rule"* ]]
}

@test "macOS links: the project grant never reopens a block's resolved target" {
  setup_link_home
  # The project sits under the blocked ~/Library, so it is re-allowed after
  # the blocks; ~/.aws resolves into it and must be denied again after that.
  mkdir -p "$LINK_HOME/Library/proj/aws"
  rm "$LINK_HOME/.aws"
  ln -s Library/proj/aws "$LINK_HOME/.aws"
  run env HOME="$LINK_HOME" _SCODE_PLATFORM=darwin \
    "$SCODE" --dry-run -C "$LINK_HOME/Library/proj" -- true
  [ "$status" -eq 0 ]
  local grant_line deny_line
  grant_line="$(last_line_of "$output" "  (subpath \"$LINK_HOME_REAL/Library/proj\")")"
  deny_line="$(last_line_of "$output" "  (subpath \"$LINK_HOME_REAL/Library/proj/aws\")")"
  [ "$grant_line" -gt 0 ]
  [ "$deny_line" -gt "$grant_line" ]
}

@test "macOS links: a custom block resolving onto the project is refused" {
  setup_link_home
  ln -s work "$LINK_HOME/work-link"
  link_darwin_dry_run --block "$LINK_HOME/work-link"
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom block covers the project directory"* ]]
}

@test "macOS links: an allowed child of a resolved target is reopened after the block" {
  setup_link_home
  mkdir -p "$LINK_HOME/dotfiles/aws/public"
  link_darwin_dry_run --allow "$LINK_HOME/dotfiles/aws/public"
  [ "$status" -eq 0 ]
  local deny_line allow_line
  deny_line="$(last_line_of "$output" "  (subpath \"$LINK_HOME_REAL/dotfiles/aws\")")"
  allow_line="$(last_line_of "$output" "  (subpath \"$LINK_HOME_REAL/dotfiles/aws/public\")")"
  [ "$deny_line" -gt 0 ]
  [ "$allow_line" -gt "$deny_line" ]
}

@test "macOS links: --allow on a built-in block's link name lifts the block" {
  setup_link_home
  link_darwin_dry_run --allow "$LINK_HOME/.aws"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$LINK_HOME_REAL/.aws\")"* ]]
  [[ "$output" != *"(subpath \"$LINK_HOME_REAL/dotfiles/aws\")"* ]]
}

@test "links: --allow on a built-in block's link name lifts the Linux block too" {
  setup_link_home
  run env HOME="$LINK_HOME" _SCODE_PLATFORM=linux \
    "$SCODE" --dry-run -C "$LINK_HOME/work" --allow "$LINK_HOME/.aws" -- true
  [ "$status" -eq 0 ]
  [[ "$output" != *"--tmpfs $LINK_HOME_REAL/dotfiles/aws "* ]]
  [[ "$output" != *"--tmpfs $LINK_HOME_REAL/.aws "* ]]
}

# ---------- Runtime (sandbox-exec) ----------

@test "macOS runtime: linked block targets are unreadable, an unrelated sibling is readable" {
  require_runtime_sandbox
  setup_link_home
  local d="$LINK_HOME/dotfiles"
  # The script prints a count and the sibling's content; the fixture values
  # live only in the files, never in the command text.
  HOME="$LINK_HOME" run "$SCODE" --no-net -C "$LINK_HOME/work" -- /bin/sh -c '
    n=0
    for f in "$@"; do cat "$f" 2>/dev/null && n=$((n + 1)); done
    echo "count=$n"
    cat "'"$d"'/vim/vimrc"
  ' sh "$d/aws/credentials" "$LINK_HOME/.aws/credentials" "$d/npmrc" \
    "$LINK_HOME/.npmrc" "$d/config/gh/hosts.yml" "$LINK_HOME/.config/gh/hosts.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"count=0"* ]]
  [[ "$output" != *"fixture-value"*"count="* ]]
  [[ "$output" == *"sibling-fixture-value"* ]]
}

@test "macOS runtime: the project grant does not reopen a linked block's target" {
  require_runtime_sandbox
  setup_link_home
  local project="$LINK_HOME/Library/proj"
  mkdir -p "$project/aws" "$project/src"
  printf 'aws-fixture-value\n' > "$project/aws/credentials"
  printf 'source-fixture-value\n' > "$project/src/main.c"
  rm "$LINK_HOME/.aws"
  ln -s Library/proj/aws "$LINK_HOME/.aws"
  HOME="$LINK_HOME" run "$SCODE" --no-net -C "$project" -- /bin/sh -c '
    n=0
    cat aws/credentials 2>/dev/null && n=$((n + 1))
    echo "count=$n"
    cat src/main.c
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"count=0"* ]]
  [[ "$output" != *"aws-fixture-value"* ]]
  [[ "$output" == *"source-fixture-value"* ]]
}
