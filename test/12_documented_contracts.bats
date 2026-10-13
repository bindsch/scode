#!/usr/bin/env bats
# Regression checks for documented policy contracts.

load test_helper

@test "release documentation is checked before any tag exists" {
  local root="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TEST_PROJECT/scripts" "$TEST_PROJECT/docs"
  cp "$root/scripts/release-pins.sh" "$TEST_PROJECT/scripts/"
  cp "$root/scode" "$root/README.md" "$TEST_PROJECT/"
  cp "$root/docs/installation.md" "$TEST_PROJECT/docs/"
  run bash "$TEST_PROJECT/scripts/release-pins.sh" check
  [ "$status" -eq 0 ]
  printf '\n  RELEASE_TAG="v0.0.0"\n' > "$TEST_PROJECT/docs/installation.md"
  run bash "$TEST_PROJECT/scripts/release-pins.sh" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"installation selector is stale"* ]]
  run bash "$TEST_PROJECT/scripts/release-pins.sh" update
  [ "$status" -eq 0 ]
  run bash "$TEST_PROJECT/scripts/release-pins.sh" check
  [ "$status" -eq 0 ]
}

@test "development runtime check follows the manifest's supported majors" {
  require_node
  local script="$BATS_TEST_DIRNAME/../scripts/check-node.js" version
  for version in 22 24 26; do
    run node -e 'Object.defineProperty(process.versions, "node", {value: process.argv[1]}); require(process.argv[2]);' "$version.0.0" "$script"
    [ "$status" -eq 0 ]
  done
  for version in 20 23 25 27; do
    run node -e 'Object.defineProperty(process.versions, "node", {value: process.argv[1]}); require(process.argv[2]);' "$version.0.0" "$script"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is required"* ]]
  done
}

@test "Linux default explicitly allows an existing subtree outside base mounts" {
  local extra
  extra="$(mktemp -d)"
  extra="$(cd "$extra" && pwd -P)"
  track_cleanup "$extra"
  run env _SCODE_PLATFORM=linux "$SCODE" --dry-run -C "$TEST_PROJECT" --allow "$extra" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bind $extra $extra"* ]]
}

@test "Linux privilege masks follow explicit grants and command auto-allows" {
  local mode priv mask tail
  priv=/usr/bin/su
  [ -f "$priv" ] || skip "su fixture unavailable"
  for mode in default strict; do
    local -a flags=()
    [ "$mode" = strict ] && flags=(--strict)
    run env _SCODE_PLATFORM=linux "$SCODE" --dry-run -C "$TEST_PROJECT" "${flags[@]}" --allow /usr -- "$priv"
    [ "$status" -eq 0 ]
    mask="--ro-bind /dev/null $priv"
    [[ "$output" == *"$mask"* ]]
    tail="${output##*"$mask"}"
    [[ "$tail" != *"--bind /usr /usr"* ]]
    [[ "$tail" != *"--ro-bind $priv $priv"* ]]
  done
}

@test "macOS privilege deny follows explicit grants and command auto-allows" {
  local mode tail
  for mode in default strict; do
    local -a flags=()
    [ "$mode" = strict ] && flags=(--strict)
    run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$TEST_PROJECT" "${flags[@]}" --allow /usr -- /usr/bin/su
    [ "$status" -eq 0 ]
    tail="${output##*Privilege command restriction (final)}"
    [[ "$tail" != "$output" ]]
    [[ "$tail" == *'(deny process-exec (regex #"(/|^)(sudo|su|login|doas|pkexec)$"))'* ]]
    [[ "$tail" != *'(allow '* ]]
  done
}

@test "Cursor agent symlink is detected by its canonical launcher name" {
  mkdir -p "$TEST_PROJECT/bin"
  printf '#!/bin/sh\nexit 0\n' > "$TEST_PROJECT/bin/cursor-agent"
  chmod +x "$TEST_PROJECT/bin/cursor-agent"
  ln -s cursor-agent "$TEST_PROJECT/bin/agent"
  run "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- "$TEST_PROJECT/bin/agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict+cursor-agent"* ]]
  [[ "$output" == *"$HOME/.cursor"* ]]
}
