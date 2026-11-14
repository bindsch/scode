#!/usr/bin/env bats
load test_helper

check_teardown() {
  case "$1" in signal|quit|concurrent) require_direct_signal_delivery ;; esac
  [[ "$(uname -s)" == Darwin ]] || skip "macOS Seatbelt teardown"
  require_runtime_sandbox
  run /usr/bin/python3 -I "$BATS_TEST_DIRNAME/strict_descendant.py" "$SCODE" "$TEST_PROJECT" "$1"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "strict teardown: setsid double fork and TERM resistance" { check_teardown normal; }
@test "strict teardown: logged run" { check_teardown log; }
@test "strict teardown: parent TERM preserves status and kills detached child" { check_teardown signal; }
@test "strict teardown: parent QUIT sweeps the still-running engine too" { check_teardown quit; }
@test "strict teardown: concurrent sandbox and unrelated process survive" { check_teardown concurrent; }

@test "strict teardown: missing helper reports the residual" {
  [[ "$(uname -s)" == Darwin ]] || skip "macOS Seatbelt teardown"
  require_runtime_sandbox
  cp "$SCODE_SOURCE" "$TEST_PROJECT/scode"
  run "$TEST_PROJECT/scode" --strict -C "$TEST_PROJECT" -- /usr/bin/true
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict descendant teardown unavailable"*"detached descendants may survive"* ]]
}

@test "strict teardown: dry-run describes the conditional helper and probe" {
  run env _SCODE_PLATFORM=darwin "$SCODE" --dry-run --strict -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"conditional on /usr/bin/python3, the helper, and a successful probe"* ]]
  [[ "$output" == *"detached descendants may survive"* ]]
}

@test "strict teardown: invalid arguments produce a warning without a traceback" {
  local helper="$BATS_TEST_DIRNAME/../lib/strict-teardown.py" args
  for args in '' 'bogus' 'bogus directory' 'prepare directory extra'; do
    run python3 -I "$helper" $args
    [ "$status" -eq 1 ]
    [[ "$output" == *"scode: strict descendant teardown unavailable:"*"detached descendants may survive"* ]]
    [[ "$output" != *Traceback* ]]
  done
}

@test "strict teardown: prepare verifies the native signal ABI" {
  [[ "$(uname -s)" == Darwin ]] || skip "macOS signal ABI"
  require_runtime_sandbox
  mkdir "$TEST_PROJECT/markers"
  run /usr/bin/python3 -I "$BATS_TEST_DIRNAME/../lib/strict-teardown.py" prepare "$TEST_PROJECT/markers"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Per-run strict teardown identity"* ]]
}

@test "strict teardown: empty pidfiles wait for content" {
  run python3 -I "$BATS_TEST_DIRNAME/strict_teardown_checks.py" pidfile
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "strict teardown: prepare refuses an ABI that rejects live tokens" {
  run python3 -I "$BATS_TEST_DIRNAME/strict_teardown_checks.py" probe
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "strict teardown: signal errors do not abort other members or KILL escalation" {
  run python3 -I "$BATS_TEST_DIRNAME/strict_teardown_checks.py" signal-errors
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "strict teardown: signal cases skip under kcov before launching" {
  run env SCODE_KCOV_BINARY=coverage-guard-check bats --filter 'parent TERM|parent QUIT|concurrent sandbox' "$BATS_TEST_FILENAME"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '# skip signal delivery is not faithful under kcov')" -eq 3 ]
}

@test "strict teardown: the exit sweep runs with group signals ignored" {
  # A follow-up INT/TERM/HUP/QUIT to the process group during the exit trap
  # must not kill the helper mid-sweep (review 45578a28): the helper runs in
  # a subshell that ignores them, and ignored dispositions survive exec.
  run grep -F "(trap '' INT TERM HUP QUIT; exec /usr/bin/python3 -I \"\$SCODE_TEARDOWN_DIR/helper.py\" cleanup" "$SCODE_SOURCE"
  [ "$status" -eq 0 ]
}
