#!/usr/bin/env bats
# Exact runtime files must survive built-in blocks without exposing siblings.
load test_helper

require_runtime_files_sandbox() {
  if [[ "$(uname -s)" == Linux ]]; then
    require_linux_bwrap
  else
    /usr/bin/sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
      || skip "runtime sandbox unavailable in this environment"
  fi
}

setup_runtime_install() {
  RHOME="$TEST_PROJECT/home"
  mkdir -p "$RHOME/Documents" "$RHOME/work"
  RHOME="$(cd -P "$RHOME" && pwd -P)"
  export SCODE_CONFIG="$RHOME/empty.yaml"
  : > "$SCODE_CONFIG"
  local layout="${1:-source}"
  INSTALL="$RHOME/Documents/${2:-scode}"
  if [[ "$layout" == installed ]]; then
    LAUNCHER="$INSTALL/bin/scode"
    PRELOAD="$INSTALL/lib/scode/no-sandbox.js"
  else
    LAUNCHER="$INSTALL/scode"
    PRELOAD="$INSTALL/lib/no-sandbox.js"
  fi
  mkdir -p "$(dirname "$LAUNCHER")" "$(dirname "$PRELOAD")"
  cp "$SCODE_SOURCE" "$LAUNCHER"
  cp "$NO_SANDBOX_JS" "$PRELOAD"
  chmod +x "$LAUNCHER"
  printf 'private-fixture\n' > "$(dirname "$PRELOAD")/sibling"
  printf '#!/bin/sh\nexec node "$@"\n' > "$INSTALL/fixture-command"
  chmod +x "$INSTALL/fixture-command"
}

check_runtime_preload() {
  local mode access command="${1:-node}"
  for mode in '' --strict; do
    for access in --rw --ro; do
      HOME="$RHOME" run "$LAUNCHER" ${mode:+"$mode"} "$access" --no-net -C "$RHOME" -- \
        "$command" -e '
          const fs = require("fs");
          if (require("child_process").spawn.name !== "patchedSpawn") process.exit(11);
          for (const p of process.argv.slice(1)) {
            try { fs.readFileSync(p); process.exit(12); } catch (e) {
              if (!["ENOENT", "EACCES", "EPERM"].includes(e.code)) throw e;
            }
          }
          try { fs.openSync(process.env.SCODE_NO_SANDBOX_JS, "a"); process.exit(13); }
          catch (e) { if (!["EROFS", "EACCES", "EPERM"].includes(e.code)) throw e; }
          console.log("preload-active; siblings-hidden; preload-read-only");
        ' "$(dirname "$PRELOAD")/sibling" "$LAUNCHER"
      [ "$status" -eq 0 ]
      [[ "$output" == *"preload-active; siblings-hidden; preload-read-only"* ]]
    done
  done
}

@test "macOS: exact preload and command grants follow built-in blocks" {
  setup_runtime_install
  local mode access tail
  for mode in '' --strict; do
    for access in --rw --ro; do
      run env HOME="$RHOME" _SCODE_PLATFORM=darwin "$LAUNCHER" --dry-run ${mode:+"$mode"} \
        "$access" -C "$RHOME" -- "$INSTALL/fixture-command"
      [ "$status" -eq 0 ]
      tail="${output##*(subpath \"$RHOME/Documents\")}"
      [[ "$tail" == *"(allow file-read*"$'\n'"  (literal \"$PRELOAD\")"* ]]
      [[ "$tail" == *"(allow file-read* process-exec"$'\n'"  (literal \"$INSTALL/fixture-command\")"* ]]
      [[ "$tail" != *"(subpath \"$INSTALL"* ]]
    done
  done
}

@test "Linux: exact preload and command binds follow built-in masks" {
  setup_runtime_install
  local mode access tail
  for mode in '' --strict; do
    for access in --rw --ro; do
      run env HOME="$RHOME" _SCODE_PLATFORM=linux "$LAUNCHER" --dry-run ${mode:+"$mode"} \
        "$access" -C "$RHOME" -- "$INSTALL/fixture-command"
      [ "$status" -eq 0 ]
      [[ "$output" == *"--tmpfs $RHOME/Documents "* ]]
      tail="${output##*--tmpfs $RHOME/Documents }"
      [[ "$tail" == *"--ro-bind $PRELOAD $PRELOAD"* ]]
      [[ "$tail" == *"--ro-bind $INSTALL/fixture-command $INSTALL/fixture-command"* ]]
      [[ "$tail" != *"--bind $INSTALL "* ]]
    done
  done
}

@test "runtime: source install preload survives built-in blocks" {
  require_runtime_files_sandbox
  require_node
  setup_runtime_install
  check_runtime_preload
}

@test "runtime: packaged install preload survives built-in blocks" {
  require_runtime_files_sandbox
  require_node
  setup_runtime_install installed
  check_runtime_preload
}

@test "runtime: space-containing install preload survives built-in blocks" {
  require_runtime_files_sandbox
  require_node
  setup_runtime_install source 'scode fixture'
  check_runtime_preload
}

@test "runtime: linked built-in block preserves only exact runtime files" {
  require_runtime_files_sandbox
  require_node
  setup_runtime_install
  mv "$RHOME/Documents" "$RHOME/work/install"
  ln -s work/install "$RHOME/Documents"
  INSTALL="$RHOME/work/install/scode"
  LAUNCHER="$INSTALL/scode"
  PRELOAD="$INSTALL/lib/no-sandbox.js"
  check_runtime_preload "$INSTALL/fixture-command"
}

@test "runtime: command under built-in block remains executable with preload" {
  require_runtime_files_sandbox
  require_node
  setup_runtime_install
  check_runtime_preload "$INSTALL/fixture-command"
}

@test "runtime: symlinked preload target survives its own built-in block" {
  require_runtime_files_sandbox
  require_node
  setup_runtime_install
  mkdir -p "$RHOME/Desktop"
  mv "$PRELOAD" "$RHOME/Desktop/preload.js"
  ln -s "$RHOME/Desktop/preload.js" "$PRELOAD"
  check_runtime_preload
}

@test "custom preload blocks still suppress injection on both platforms" {
  setup_runtime_install
  local platform mode
  for platform in darwin linux; do
    for mode in '' --strict; do
      run env HOME="$RHOME" _SCODE_PLATFORM="$platform" "$LAUNCHER" --dry-run ${mode:+"$mode"} \
        -C "$RHOME" --block "$(dirname "$PRELOAD")" -- node
      [ "$status" -eq 0 ]
      [[ "$output" == *"browser preload disabled because custom policy blocks it"* ]]
      [[ "$output" != *"#   NODE_OPTIONS="* ]]
      [[ "$output" != *"(literal \"$PRELOAD\")"* ]]
      [[ "$output" != *"--ro-bind $PRELOAD $PRELOAD"* ]]
    done
  done
}

@test "custom blocks covering a space-free preload alias refuse launch and clean up" {
  # Keep the project outside /tmp, including on Linux where mktemp defaults there.
  track_cleanup "$TEST_PROJECT"
  TEST_PROJECT="$(mktemp -d /var/tmp/scode-alias-policy.XXXXXX)"
  setup_runtime_install source 'scode fixture'
  ln -s /tmp "$RHOME/tmp-link"
  local platform mode block alias
  for platform in darwin linux; do
    for mode in '' --strict; do
      for block in /tmp "$RHOME/tmp-link"; do
        run env HOME="$RHOME" _SCODE_PLATFORM="$platform" "$LAUNCHER" --dry-run ${mode:+"$mode"} \
          -C "$RHOME/work" --block "$block" -- /usr/bin/true
        [ "$status" -eq 1 ]
        [[ "$output" == *"custom policy blocks the temporary preload alias:"* ]]
        [[ "$output" != *"#   NODE_OPTIONS="* ]]
        alias="$(printf '%s\n' "$output" | sed -n 's@.*temporary preload alias: \(/tmp/[^/]*/preload.js\).*@\1@p')"
        [[ "$alias" == /tmp/scode-no-sandbox.*/preload.js ]]
        [ ! -e "${alias%/*}" ]
      done
    done
  done
  HOME="$RHOME" run "$LAUNCHER" -C "$RHOME/work" --block /tmp -- \
    /bin/sh -c 'echo child-started; touch "$HOME/work/child-started"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"custom policy blocks the temporary preload alias:"* ]]
  [[ "$output" != *child-started* ]]
  [ ! -e "$RHOME/work/child-started" ]
}
