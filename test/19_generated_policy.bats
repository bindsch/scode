#!/usr/bin/env bats
load test_helper

@test "precedence oracle and evaluators have independent known answers" {
  run node "$BATS_TEST_DIRNAME/policy_model_checks.js"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "generated precedence: reference model agrees with both dry-run backends" {
  run node "$BATS_TEST_DIRNAME/generated_policy.js" "$SCODE_SOURCE" "$TEST_PROJECT" matrix
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "reviewer AWS chain: custom child restoration preserves allowed.txt" {
  run node "$BATS_TEST_DIRNAME/generated_policy.js" "$SCODE_SOURCE" "$TEST_PROJECT" aws
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "reviewer SSH chain: custom child restoration preserves known_hosts" {
  run node "$BATS_TEST_DIRNAME/generated_policy.js" "$SCODE_SOURCE" "$TEST_PROJECT" ssh
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "runtime exceptions add reads without revoking explicit writes" {
  run node "$BATS_TEST_DIRNAME/generated_policy.js" "$SCODE_SOURCE" "$TEST_PROJECT" runtime-grants
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "project inside a resolved built-in block keeps sibling credentials hidden" {
  run node "$BATS_TEST_DIRNAME/generated_policy.js" "$SCODE_SOURCE" "$TEST_PROJECT" nested-project
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "linked custom blocks stay retained under allows covering only written ancestors" {
  run node "$BATS_TEST_DIRNAME/generated_policy.js" "$SCODE_SOURCE" "$TEST_PROJECT" custom-links
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "runtime: linked blocks preserve file exceptions and hide their siblings" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  local fixture="$TEST_PROJECT/home" mode access builtin
  mkdir -p "$fixture/project" "$fixture/holder/allowed" "$fixture/secret/child" "$fixture/other"
  fixture="$(cd -P "$fixture" && pwd -P)"
  export SCODE_CONFIG="$fixture/empty.yaml"
  : > "$SCODE_CONFIG"
  printf 'allowed-fixture\n' > "$fixture/secret/allowed.txt"
  printf 'allowed-fixture\n' > "$fixture/secret/known_hosts"
  printf 'private-fixture\n' > "$fixture/secret/private"
  printf 'private-fixture\n' > "$fixture/holder/private"
  printf 'private-fixture\n' > "$fixture/other/private"
  ln -s "$fixture/secret" "$fixture/holder/allowed/link"
  ln -s "$fixture/other" "$fixture/secret/child/nested"
  ln -s "$fixture/secret/child/nested" "$fixture/.gnupg"
  for builtin in .aws .ssh; do
    ln -s "$fixture/holder/allowed/link" "$fixture/$builtin"
  done
  for mode in '' --strict; do
    for access in --rw --ro; do
      HOME="$fixture" run "$SCODE" ${mode:+"$mode"} "$access" --no-net -C "$fixture/project" \
        --block "$fixture/holder" --allow "$fixture/holder/allowed" \
        --allow "$fixture/secret/allowed.txt" --allow "$fixture/secret/known_hosts" \
        --allow "$fixture/secret/child" -- /bin/sh -c '
          cat "$HOME/secret/allowed.txt" || exit 11
          cat "$HOME/secret/known_hosts" || exit 12
          echo writable >> "$HOME/secret/allowed.txt" || exit 13
          cat "$HOME/secret/private" 2>/dev/null && exit 14
          cat "$HOME/holder/private" 2>/dev/null && exit 15
          cat "$HOME/secret/child/nested/private" 2>/dev/null && exit 16
          exit 0
        '
      [ "$status" -eq 0 ]
      [[ "$output" == *allowed-fixture* ]]
      [[ "$output" != *private-fixture* ]]
    done
  done
}

@test "runtime: exact preload and command exceptions preserve writable child grants" {
  if [[ "$(uname -s)" == Linux ]]; then require_linux_bwrap; else require_runtime_sandbox; fi
  local fixture="$TEST_PROJECT/home" mode access
  mkdir -p "$fixture/project" "$fixture/.gnupg/lib"
  fixture="$(cd -P "$fixture" && pwd -P)"
  export SCODE_CONFIG="$fixture/empty.yaml"
  : > "$SCODE_CONFIG"
  cp "$SCODE_SOURCE" "$fixture/.gnupg/scode"
  cp "$NO_SANDBOX_JS" "$fixture/.gnupg/lib/no-sandbox.js"
  cat > "$fixture/.gnupg/fixture-command" <<'SH'
#!/bin/sh
printf '\n# writable\n' >> "$0" || exit 11
printf '\n// writable\n' >> "$HOME/.gnupg/lib/no-sandbox.js" || exit 12
echo runtime-files-writable
SH
  chmod +x "$fixture/.gnupg/scode" "$fixture/.gnupg/fixture-command"
  for mode in '' --strict; do
    for access in --rw --ro; do
      HOME="$fixture" run "$fixture/.gnupg/scode" ${mode:+"$mode"} "$access" --no-net -C "$fixture/project" \
        --allow "$fixture/.gnupg/fixture-command" --allow "$fixture/.gnupg/lib/no-sandbox.js" \
        -- "$fixture/.gnupg/fixture-command"
      [ "$status" -eq 0 ]
      [[ "$output" == *runtime-files-writable* ]]
    done
  done
}
