#!/usr/bin/env bats
# Usage accounting — SCODE_ACCOUNT_FILE / SCODE_ACCOUNT_ID

load test_helper

@test "accounting off by default: no record is written" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ ! -e "$acct" ]
}

@test "SCODE_ACCOUNT_FILE appends one JSON line with scratch usage" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" SCODE_ACCOUNT_ID="job-42" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$acct" ]
  [ "$(wc -l < "$acct")" -eq 1 ]
  local line
  line="$(cat "$acct")"
  [[ "$line" == *'"event":"scode_exit"'* ]]
  [[ "$line" == *'"exit_code":0'* ]]
  [[ "$line" == *'"account_id":"job-42"'* ]]
  grep -q '"scratch_kib":[0-9]' <<< "$line"
  [[ "$line" == *'"scratch_path":"/'* ]]
}

@test "account variables are not passed to the sandboxed child" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # printenv exits 1 when the variable is unset; that is the assertion.
  # (bats' run captures scode's unknown-command warning too, so assert on
  # the variable never appearing rather than on empty output.)
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- printenv SCODE_ACCOUNT_FILE
  [ "$status" -eq 1 ]
  [[ "$output" != *"SCODE_ACCOUNT_FILE"* ]]
  # The parent still recorded the run even though the child saw nothing.
  [ -f "$acct" ]
}

@test "failed child commands still record their exit code" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- sh -c 'exit 7'
  [ "$status" -eq 7 ]
  local line
  line="$(cat "$acct")"
  [[ "$line" == *'"exit_code":7'* ]]
}

@test "accounting failure never skips scratch teardown (du on mode-000 dir)" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # The child's TMPDIR is the scratch dir; an untraversable directory makes
  # du fail mid-walk. Errexit in the trap must not skip teardown or perturb
  # the child's exit code.
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- sh -c 'mkdir -m 000 "$TMPDIR/d"'
  [ "$status" -eq 0 ]
  [ -f "$acct" ]
  local scratch
  scratch="$(sed -n 's/.*"scratch_path":"\([^"]*\)".*/\1/p' "$acct")"
  [ -n "$scratch" ]
  [ ! -d "$scratch" ]
  # du fails mid-walk and still prints a partial total; the record must say
  # null + why, never a silently underreported number.
  grep -q '"scratch_kib":null' "$acct"
  grep -q '"reason":"du_failed"' "$acct"
}

@test "non-regular sink (FIFO) is rejected instead of blocking the exit trap" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.fifo"
  mkfifo "$acct"
  # A FIFO with no reader would hang the EXIT-trap append forever, so
  # arming must refuse it; the run itself completes normally.
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a regular file"* ]]
  [[ "$output" == *"accounting disabled"* ]]
}

@test "symlinked sink is rejected at arm time, target untouched" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/link.jsonl"
  printf 'outside\n' > "$TEST_PROJECT/outside.txt"
  ln -s "$TEST_PROJECT/outside.txt" "$acct"
  # The EXIT-trap append follows paths, so a symlink sink would make scode
  # write through it with full privileges. Arm time must refuse instead.
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a regular file"* ]]
  [[ "$output" == *"accounting disabled"* ]]
  [ "$(cat "$TEST_PROJECT/outside.txt")" = "outside" ]
}

@test "a sink parent swapped for a symlink mid-run drops the record" {
  require_runtime_sandbox
  # The command itself is the attacker here: the sink sits in a project
  # subdirectory, and the engine swaps that directory for a symlink aimed
  # at a sibling the command can also write. The append follows paths, so
  # without the ancestor fingerprint the unsandboxed parent would write
  # through the link. The run's own status stays 0 -- accounting fails
  # invisibly -- and the record must land nowhere.
  local proj="$TEST_PROJECT/proj"
  local outside="$TEST_PROJECT/outside"
  mkdir -p "$proj/logs" "$outside"
  local acct="$proj/logs/account.jsonl"
  local swap="$TEST_PROJECT/swap.sh"
  cat > "$swap" <<SWAPEOF
#!/bin/bash
cd "$proj" || exit 9
mv logs logs.real && ln -s "$outside" logs || exit 7
exit 0
SWAPEOF
  chmod +x "$swap"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$proj" -- "$swap"
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed during the run"* ]]
  [[ ! -e "$outside/account.jsonl" ]]
  [[ ! -e "$acct" ]]
}

@test "a symlinked ancestor whose target is swapped mid-run drops the record" {
  require_runtime_sandbox
  # The fingerprint follows links: an ancestor that already is a symlink
  # is tracked by the directory the traversal reaches, not by the link's
  # own inode. Swapping the link's target for a different directory
  # mid-run therefore changes the fingerprint exactly like a swapped
  # directory would, and the record is dropped before the append can
  # follow the redirect.
  local proj="$TEST_PROJECT/proj"
  local real="$TEST_PROJECT/real"
  local outside="$TEST_PROJECT/outside"
  mkdir -p "$proj" "$real" "$outside"
  ln -s "$real" "$proj/alias"
  local acct="$proj/alias/account.jsonl"
  local swap="$TEST_PROJECT/swap-link.sh"
  cat > "$swap" <<SWAPEOF
#!/bin/bash
cd "$proj" || exit 9
# The sink already exists here: accounting opens and creates it at arm
# time, before the engine runs, so the directory is not empty.
rm -f "$real/account.jsonl"
rmdir "$real" && ln -s "$outside" "$real" || exit 7
exit 0
SWAPEOF
  chmod +x "$swap"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$proj" -- "$swap"
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed during the run"* ]]
  [[ ! -e "$outside/account.jsonl" ]]
  [[ ! -e "$acct" ]]
}

@test "a sink under a missing ancestor directory disables accounting and runs the command" {
  require_runtime_sandbox
  # An unreadable or missing ancestor leaves an "x" slot in the armed
  # fingerprint; the documented degrade is a warning plus a disabled
  # accounting, never a failed run.
  local acct="$TEST_PROJECT/missing/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not read every directory"* ]]
  [[ ! -e "$acct" ]]
}

@test "an accounting warning to a dead stderr reader cannot kill the exit trap" {
  require_runtime_sandbox
  # An accounting diagnostic at write time lands on stderr. When the
  # reader on that pipe is already gone, the write dies by SIGPIPE, and
  # no || true catches a signal death. The write happens inside the
  # EXIT trap, where the run still owes the record, the teardown, and
  # the true exit status: a trap killed mid-way replaces the status
  # with 141 and skips the rest of the teardown. The command below
  # forces the write-time sink-replaced warning, and the harness
  # warning has already taken the stderr reader down; the trap ignores
  # SIGPIPE for its own writes, mid-run writes keep the conventional
  # disposition.
  local acct="$TEST_PROJECT/account.jsonl"
  : > "$acct"
  local swap="$TEST_PROJECT/swap-sink.sh"
  printf '#!/bin/bash\nexec 2>/dev/null\nmv "$1" "$1.orig" && : > "$1"\n' > "$swap"
  chmod +x "$swap"
  SCODE_ACCOUNT_FILE="$acct" run bash -c '
    exec 2> >(exec /bin/sh -c "exec head -c1 >/dev/null")
    exec "$1" -C "$2" -- /bin/bash "$3" "$4"
  ' _ "$SCODE" "$TEST_PROJECT" "$swap" "$acct"
  [ "$status" -eq 0 ]
  [[ ! -s "$acct" ]]
}

@test "a sink replaced by another regular file mid-run drops the record" {
  require_runtime_sandbox
  # The append travels through the descriptor opened when accounting
  # was armed, so a sink swapped mid-run cannot redirect the write --
  # and the write-time identity check refuses to pour the record into a
  # file the run did not open. The command is the attacker: it moves
  # the sink aside and puts a fresh regular file in its place. The
  # record is dropped with a warning, and the replacement stays empty.
  local acct="$TEST_PROJECT/account.jsonl"
  : > "$acct"
  local swap="$TEST_PROJECT/swap-sink.sh"
  printf '#!/bin/bash\nexec 2>/dev/null\nmv "$1" "$1.orig" && : > "$1"\n' > "$swap"
  chmod +x "$swap"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- /bin/bash "$swap" "$acct"
  [ "$status" -eq 0 ]
  [[ "$output" == *"replaced during the run"* ]]
  [[ ! -s "$acct" ]]
  [[ -e "$TEST_PROJECT/account.jsonl.orig" ]]
  # The append must never reopen the path: the only open of the sink is
  # the arm-time descriptor, and the write goes through that pinned fd.
  [ "$(grep -c 'exec 4>>' "$SCODE_SOURCE")" -eq 1 ]
}

@test "SIGTERM during a run records the conventional exit code" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # A fatal signal leaves $? stale (typically 0); the record must carry the
  # conventional code instead. The log-file path runs the engine as a child,
  # so TERM is forwarded promptly rather than deferred to the child's exit.
  SCODE_ACCOUNT_FILE="$acct" "$SCODE" -C "$TEST_PROJECT" --log "$TEST_PROJECT/run.log" -- sleep 30 &
  local wrapper_pid=$!
  sleep 2
  local tpgid pgid
  tpgid="$(ps -o tpgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  pgid="$(ps -o pgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  if [[ -n "$tpgid" && "$tpgid" == "$pgid" ]]; then
    # scode shares the terminal's foreground group here, so this TERM is a
    # group signal by classification and the pid-forward path cannot run.
    # The runner absorbs it without exiting, so stop the run explicitly
    # and skip; the group path is covered by the pty test.
    kill -TERM "$wrapper_pid" 2>/dev/null || true
    local w=0
    while kill -0 "$wrapper_pid" 2>/dev/null && (( w < 10 )); do sleep 0.5; w=$(( w + 1 )); done
    kill -KILL "$wrapper_pid" 2>/dev/null || true
    wait "$wrapper_pid" 2>/dev/null || true
    skip "scode is the terminal's foreground group; the group path absorbs the TERM"
  fi
  kill -TERM "$wrapper_pid"
  local rc=0
  wait "$wrapper_pid" || rc=$?
  [ "$rc" -eq 143 ]
  grep -q '"exit_code":143' "$acct"
  local scratch
  scratch="$(sed -n 's/.*"scratch_path":"\([^"]*\)".*/\1/p' "$acct")"
  [ -n "$scratch" ]
  [ ! -d "$scratch" ]
}

@test "SIGQUIT during a run records the conventional exit code" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # QUIT is fatal without special handling: the engine holds SIG_DFL for
  # it, and scode's own handler exits 131 so the record and the teardown
  # still happen -- bash runs no EXIT trap for an untrapped fatal signal,
  # which is exactly what the handler prevents. A pid-aimed QUIT leaves
  # the engine running, the same outcome as SIGKILL; the engine is a
  # sleep 5, so such an orphan is bounded. Shells start
  # asynchronous children with QUIT ignored, and bash can neither trap
  # nor reset an entry-ignored signal, so the run is started through a
  # tiny executor that restores the default disposition first -- the one
  # a foreground run on a terminal already has.
  SCODE_ACCOUNT_FILE="$acct" python3 -c '
import os, signal, sys
signal.signal(signal.SIGQUIT, signal.SIG_DFL)
os.execve(sys.argv[1], sys.argv[1:], os.environ)
' "$SCODE" -C "$TEST_PROJECT" --log "$TEST_PROJECT/quit.log" -- sleep 5 &
  local wrapper_pid=$!
  sleep 2
  kill -QUIT "$wrapper_pid"
  local rc=0
  wait "$wrapper_pid" || rc=$?
  [ "$rc" -eq 131 ]
  grep -q '"exit_code":131' "$acct"
  local scratch
  scratch="$(sed -n 's/.*"scratch_path":"\([^"]*\)".*/\1/p' "$acct")"
  [ -n "$scratch" ]
  [ ! -d "$scratch" ]
}

@test "teardown permission repair touches only directories, never linked files" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # A file the child hard-links into scratch shares its inode with the
  # outside copy. The repair pass must open locked directories for removal
  # without rewriting file modes, or the outside copy changes too.
  printf 'outside\n' > "$TEST_PROJECT/outside.txt"
  chmod 0444 "$TEST_PROJECT/outside.txt"
  # Link first, then lock: the mode-500 directory is what forces the repair
  # pass, and the link must exist before it. The inner script travels in a
  # variable so $TMPDIR expands inside the sandbox, not in this shell -- and
  # the child confirms the link was created, so setup that silently failed
  # cannot pass for coverage.
  local inner='mkdir "$TMPDIR/d" && ln "$TEST_PROJECT/outside.txt" "$TMPDIR/d/linked" && chmod 500 "$TMPDIR/d" && echo link-created'
  SCODE_ACCOUNT_FILE="$acct" TEST_PROJECT="$TEST_PROJECT" run "$SCODE" -C "$TEST_PROJECT" -- sh -c "$inner"
  [ "$status" -eq 0 ]
  [[ "$output" == *"link-created"* ]]
  local scratch
  scratch="$(sed -n 's/.*"scratch_path":"\([^"]*\)".*/\1/p' "$acct")"
  [ -n "$scratch" ]
  [ ! -d "$scratch" ]
  [ ! -w "$TEST_PROJECT/outside.txt" ]
  [ "$(cat "$TEST_PROJECT/outside.txt")" = "outside" ]
}

@test "SIGTERM on the default path stops promptly and records 143" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # The default (no --log) path must forward TERM as promptly as the logged
  # one, and to the engine itself: the launcher execs, so a forwarded signal
  # reaches the process running the command instead of killing an
  # intermediary and orphaning the chain. Two assertions: the elapsed-time
  # bound catches a deferred trap (the old behavior answered only after the
  # command finished on its own), and the sandboxed watcher -- which exits
  # once kill -0 on its parent fails -- must be gone after the engine died.
  local watcher='while kill -0 "$PPID" 2>/dev/null; do sleep 0.2; done'
  SCODE_ACCOUNT_FILE="$acct" "$SCODE" -C "$TEST_PROJECT" -- sh -c "$watcher" scode-term-watch-marker &
  local wrapper_pid=$!
  sleep 2
  local tpgid pgid
  tpgid="$(ps -o tpgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  pgid="$(ps -o pgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  if [[ -n "$tpgid" && "$tpgid" == "$pgid" ]]; then
    # Group-signal environment: the forward path cannot run here. Stop
    # the run and the watcher, then skip; the group path is covered by
    # the pty test.
    kill -TERM "$wrapper_pid" 2>/dev/null || true
    local w=0
    while kill -0 "$wrapper_pid" 2>/dev/null && (( w < 10 )); do sleep 0.5; w=$(( w + 1 )); done
    kill -KILL "$wrapper_pid" 2>/dev/null || true
    wait "$wrapper_pid" 2>/dev/null || true
    pkill -f scode-term-watch-marker 2>/dev/null || true
    skip "scode is the terminal's foreground group; the group path absorbs the TERM"
  fi
  local started=$SECONDS
  kill -TERM "$wrapper_pid"
  local rc=0
  wait "$wrapper_pid" || rc=$?
  local elapsed=$(( SECONDS - started ))
  [ "$rc" -eq 143 ]
  [ "$elapsed" -lt 15 ]
  grep -q '"exit_code":143' "$acct"
  local scratch
  scratch="$(sed -n 's/.*"scratch_path":"\([^"]*\)".*/\1/p' "$acct")"
  [ -n "$scratch" ]
  [ ! -d "$scratch" ]
  # The watcher gets a short grace to notice the engine is gone, then it
  # must be gone: a signal that kills only an intermediary leaves it behind.
  local waited=0
  while pgrep -f scode-term-watch-marker >/dev/null 2>&1 && (( waited < 10 )); do
    sleep 0.5
    waited=$(( waited + 1 ))
  done
  ! pgrep -f scode-term-watch-marker >/dev/null 2>&1
}

@test "SIGINT aimed at scode's pid is forwarded promptly and records 130" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # Under bats scode starts asynchronously, so bash hands it a SIG_IGN for
  # SIGINT that would make the trap inoperative; the wrapper resets the
  # disposition before exec'ing scode. When scode's group happens to be the
  # terminal's foreground group, the INT is a group signal by definition and
  # scode does not forward it -- that path is covered by the pty test below.
  local reset='import signal, os, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])'
  SCODE_ACCOUNT_FILE="$acct" /usr/bin/python3 -c "$reset" "$SCODE" -C "$TEST_PROJECT" -- sleep 30 &
  local wrapper_pid=$!
  sleep 2
  local tpgid pgid
  tpgid="$(ps -o tpgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  pgid="$(ps -o pgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  if [[ -n "$tpgid" && "$tpgid" == "$pgid" ]]; then
    # The runner absorbs a group TERM without exiting, so the plain wait
    # below would block for the engine's whole lifetime. Stop the run on
    # a bound instead, then skip.
    kill -TERM "$wrapper_pid" 2>/dev/null || true
    local w=0
    while kill -0 "$wrapper_pid" 2>/dev/null && (( w < 10 )); do sleep 0.5; w=$(( w + 1 )); done
    kill -KILL "$wrapper_pid" 2>/dev/null || true
    wait "$wrapper_pid" 2>/dev/null || true
    skip "scode is the terminal's foreground group; the group path absorbs the INT"
  fi
  local started=$SECONDS
  kill -INT "$wrapper_pid"
  local rc=0
  wait "$wrapper_pid" || rc=$?
  local elapsed=$(( SECONDS - started ))
  [ "$rc" -eq 130 ]
  [ "$elapsed" -lt 15 ]
  grep -q '"exit_code":130' "$acct"
  local scratch
  scratch="$(sed -n 's/.*"scratch_path":"\([^"]*\)".*/\1/p' "$acct")"
  [ -n "$scratch" ]
  [ ! -d "$scratch" ]
}

@test "a terminal-group SIGINT is delivered once and the engine's status stands" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # A pty makes scode a session leader whose group is the terminal's
  # foreground group, so ^C is a group INT: the engine must receive exactly
  # one (a second copy would fire its handler twice or kill it mid-handler),
  # scode must report the engine's own status, and the scratch must be torn
  # down. The engine handles the INT and exits 0 on purpose -- the forced
  # 130 this test replaces would fail the assertion. The one-line
  # not-forwarding note is expected here too: scode cannot tell a group ^C
  # from a pid-directed one.
  local harness="$TEST_PROJECT/pty_int.py"
  write_pty_int_harness "$harness"
  SCODE="$SCODE" PROJ="$TEST_PROJECT" ACCT="$acct" MODE=group \
    run /usr/bin/python3 "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc: 0"* ]]
  [[ "$output" == *"handler fires: 1"* ]]
  [[ "$output" == *"record exit_code: 0"* ]]
  [[ "$output" == *"scratch torn down: True"* ]]
  [[ "$output" == *"forward-warning: yes"* ]]
}

@test "a SIGINT aimed at scode's pid on a pty is treated as a terminal-group signal" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # On a pty, scode's group is the foreground group, so a pid-directed INT
  # is indistinguishable from a group INT by membership alone. scode
  # forwards nothing -- a forwarded copy double-signaled engines that were
  # still handling the first signal -- and warns on stderr instead: the
  # run continues per the engine's will. This engine handles INT and would
  # exit 0 on one, so handler-fires must stay 0: the engine runs out its
  # short clock and exits naturally, the record carries that status, and
  # the teardown happens on schedule.
  local harness="$TEST_PROJECT/pty_int.py"
  write_pty_int_harness "$harness"
  SCODE="$SCODE" PROJ="$TEST_PROJECT" ACCT="$acct" MODE=pid SLEEP=2 \
    run /usr/bin/python3 "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc: 0"* ]]
  [[ "$output" == *"handler fires: 0"* ]]
  [[ "$output" == *"record exit_code: 0"* ]]
  [[ "$output" == *"scratch torn down: True"* ]]
  [[ "$output" == *"forward-warning: yes"* ]]
}

@test "a terminal-group SIGINT reaches a handler that continues exactly once" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # One ^C must be one delivery even when the engine stays alive: this
  # engine's handler records the signal and returns, and the engine
  # outlives the signal by design. A scode that forwarded a copy because
  # the engine "should have exited by now" would fire the handler a
  # second time around the two-second mark -- that regression is what
  # this test pins. The engine then runs out its clock and exits
  # naturally; the record carries that status.
  local harness="$TEST_PROJECT/pty_int.py"
  write_pty_int_harness "$harness"
  SCODE="$SCODE" PROJ="$TEST_PROJECT" ACCT="$acct" MODE=group MARKER=int-seen \
    INNER='int_seen(){ echo int-seen; }; trap int_seen INT; echo engine-ready; sleep 3 & until wait $!; do kill -0 $! 2>/dev/null || break; done; echo engine-done' \
    DEADLINE=15 \
    run /usr/bin/python3 "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc: 0"* ]]
  [[ "$output" == *"handler fires: 1"* ]]
  [[ "$output" == *"record exit_code: 0"* ]]
  [[ "$output" == *"scratch torn down: True"* ]]
}

@test "a terminal-group SIGTERM reaches a handler that continues exactly once" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # A group TERM cannot be typed on a terminal, so the harness signals
  # the pty's foreground group the way a supervisor would. scode is in
  # that group too: its handler must classify the TERM as terminal-group
  # and not forward a second copy, or this engine's one-shot handler
  # fires twice -- the regression this test pins. The engine's wait
  # loop stops once the background sleep is gone, so a group TERM that
  # reaches the sleep as well cannot spin the loop past the engine's
  # own exit. The engine then runs out its clock and exits naturally;
  # the record carries that status.
  local harness="$TEST_PROJECT/pty_int.py"
  write_pty_int_harness "$harness"
  SCODE="$SCODE" PROJ="$TEST_PROJECT" ACCT="$acct" MODE=groupterm MARKER=term-seen \
    INNER='term_seen(){ echo term-seen; }; trap term_seen TERM; echo engine-ready; sleep 3 & until wait $!; do kill -0 $! 2>/dev/null || break; done; echo engine-done' \
    DEADLINE=15 \
    run /usr/bin/python3 "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc: 0"* ]]
  [[ "$output" == *"handler fires: 1"* ]]
  [[ "$output" == *"forward-warning: yes"* ]]
  [[ "$output" == *"record exit_code: 0"* ]]
  [[ "$output" == *"scratch torn down: True"* ]]
}

@test "a SIGINT during scode's startup is delivered and the engine never launches" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # An INT that lands after the argument loop but long before any launch
  # chain exists is answered by scode's top-level traps: the run ends 130
  # before any runner. Sending on the unknown-harness warning makes the
  # arrival deterministic: the warning is printed during engine
  # validation, after the argument loop has armed accounting and created
  # the scratch, but long before the engine execs.
  local harness="$TEST_PROJECT/pty_int.py"
  write_pty_int_harness "$harness"
  SCODE="$SCODE" PROJ="$TEST_PROJECT" ACCT="$acct" MODE=onstring SLEEP=8 \
    DEADLINE=15 \
    run /usr/bin/python3 "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc: 130"* ]]
  [[ "$output" == *"engine seen: no"* ]]
  [[ "$output" == *"record exit_code: 130"* ]]
  [[ "$output" == *"scratch torn down: True"* ]]
}

@test "the launcher delivers a recorded INT at the restore and the engine never execs" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  # The fork-to-restore window is the pending-INT file's own territory,
  # and no external observer can hit it from a pty without racing the
  # launch chain's subprocess phases. The chain's launcher function is
  # deterministic on its own, so extract it from scode and drive it
  # directly: a recorded INT must end the chain with the conventional
  # 130 before the engine execs, and an empty record must let the
  # engine exec normally.
  local launcher_src="$TEST_PROJECT/launcher.sh"
  sed -n "/^run_sandbox_engine_with_closed_fds() {/,/^}/p" "$SCODE_SOURCE" > "$launcher_src"
  [[ -s "$launcher_src" ]]
  local engine="$TEST_PROJECT/engine.sh"
  printf '#!/bin/bash\nenv >"%s"\necho engine-execed >>"%s"\n' "$TEST_PROJECT/env.log" "$TEST_PROJECT/execed.log" > "$engine"
  chmod +x "$engine"
  local pf="$TEST_PROJECT/pending-int"
  # sandbox-exec's -p takes the profile text, not a path -- the same
  # shape scode's generated profile travels in.
  local profile='(version 1) (allow default)'

  # A recorded INT: one delivery at the restore, no engine.
  printf 'INT\n' > "$pf"
  SCODE_CALLER_PATH="$PATH" run bash -c '
    source "$1"
    _SCODE_PENDING_INT_FILE="$2"
    run_sandbox_engine_with_closed_fds "$3" -p "$4" -- "$5"
  ' _ "$launcher_src" "$pf" "/usr/bin/sandbox-exec" "$profile" "$engine"
  [ "$status" -eq 130 ]
  [[ ! -e "$TEST_PROJECT/execed.log" ]]

  # An empty record: the chain execs the engine.
  : > "$pf"
  SCODE_CALLER_PATH="$PATH" run bash -c '
    source "$1"
    _SCODE_PENDING_INT_FILE="$2"
    run_sandbox_engine_with_closed_fds "$3" -p "$4" -- "$5"
  ' _ "$launcher_src" "$pf" "/usr/bin/sandbox-exec" "$profile" "$engine"
  [ "$status" -eq 0 ]
  grep -q engine-execed "$TEST_PROJECT/execed.log"
  # The chain must not carry the handshake names into the engine's
  # environment, on the branches this host can reach.
  ! grep -q '^SCODE_PENDING_INT_FILE=' "$TEST_PROJECT/env.log"
  ! grep -q '^SCODE_TRAP_BUSY=' "$TEST_PROJECT/env.log"
  # The no-interpreter fallback branch execs the engine straight from
  # bash, so the same rule gets a byte-level pin there: the unset
  # sits before that branch's exec.
  grep -q 'unset SCODE_PENDING_INT_FILE SCODE_TRAP_BUSY' "$launcher_src"

  # On macOS /usr/bin/python3 is a shim that resolves the interpreter
  # through xcrun and honors DEVELOPER_DIR before any python code runs,
  # so the launcher must move the variable aside for the shim and
  # restore it for the engine. A developer directory the caller did not
  # mean to expose would otherwise run code ahead of the sandbox: with
  # a bogus DEVELOPER_DIR the shim fails and the engine never execs.
  # The value the caller supplied still has to reach the engine intact,
  # so the run below asserts both halves.
  rm -f "$TEST_PROJECT/execed.log" "$TEST_PROJECT/env.log"
  SCODE_CALLER_PATH="$PATH" DEVELOPER_DIR="$TEST_PROJECT/no-devdir" run bash -c '
    source "$1"
    _SCODE_PENDING_INT_FILE="$2"
    run_sandbox_engine_with_closed_fds "$3" -p "$4" -- "$5"
  ' _ "$launcher_src" "$pf" "/usr/bin/sandbox-exec" "$profile" "$engine"
  [ "$status" -eq 0 ]
  grep -q engine-execed "$TEST_PROJECT/execed.log"
  grep -q "^DEVELOPER_DIR=$TEST_PROJECT/no-devdir\$" "$TEST_PROJECT/env.log"

  # A record that lands while the launcher is already settling: the
  # mark directory is held in place, the chain starts, and a helper
  # appends the record and removes the mark a moment later -- the shape
  # of an INT whose trap classification finishes after the launcher's
  # first mark check. The launcher must wait for the mark to disappear
  # and read the record: no engine, 130.
  rm -f "$TEST_PROJECT/execed.log"
  : > "$pf"
  local bf="$TEST_PROJECT/trap-busy-dir/busy"
  mkdir -p "$bf"
  local late="$TEST_PROJECT/late-record.sh"
  printf '#!/bin/bash\nsleep 0.1\nprintf "INT\\n" >>"%s"\nrmdir "%s"\n' "$pf" "$bf" > "$late"
  chmod +x "$late"
  SCODE_CALLER_PATH="$PATH" run bash -c '
    source "$1"
    _SCODE_PENDING_INT_FILE="$2"
    _SCODE_TRAP_BUSY="$6"
    "$7" &
    run_sandbox_engine_with_closed_fds "$3" -p "$4" -- "$5"
  ' _ "$launcher_src" "$pf" "/usr/bin/sandbox-exec" "$profile" "$engine" "$bf" "$late"
  [ "$status" -eq 130 ]
  [[ ! -e "$TEST_PROJECT/execed.log" ]]
}

@test "a terminal-group SIGINT on the --log path reaches the engine exactly once" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # The --log path launches the same launcher function -- it is the
  # command run_with_stderr_log starts -- so the SIG_DFL restore applies
  # there too: the engine must trap the ^C and survive it exactly once,
  # with the log still written. Pins the log path against a future that
  # launches the engine around the launcher again.
  local harness="$TEST_PROJECT/pty_int.py"
  write_pty_int_harness "$harness"
  SCODE="$SCODE" PROJ="$TEST_PROJECT" ACCT="$acct" MODE=group SLEEP=2 \
    EXTRA_ARGS="--log $TEST_PROJECT/run.log" DEADLINE=12 \
    run /usr/bin/python3 "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc: 0"* ]]
  [[ "$output" == *"handler fires: 1"* ]]
  [[ "$output" == *"forward-warning: yes"* ]]
  [[ "$output" == *"record exit_code: 0"* ]]
  [[ "$output" == *"scratch torn down: True"* ]]
  [[ -s "$TEST_PROJECT/run.log" ]]
}

@test "stdin reaches the command on the default path" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # Backgrounding the engine for prompt signal forwarding must not cost the
  # command its stdin: bash gives an async child /dev/null unless the launch
  # carries an explicit stdin redirection.
  local out rc=0
  out="$(printf 'piped-input-survives\n' | SCODE_ACCOUNT_FILE="$acct" "$SCODE" -C "$TEST_PROJECT" -- cat)" || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" == *"piped-input-survives"* ]]
}

@test "sandboxed command does not inherit bash's ignored SIGINT/SIGQUIT" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # Bash applies SIGINT (and SIGQUIT) as SIG_IGN to an asynchronous child
  # when job control is off, and the disposition survives every exec in the
  # launcher chain -- so a command without its own handlers would ignore
  # the forwarded signal and the terminal's group signal while scode waited
  # it out. The launcher restores SIG_DFL for both through
  # /usr/bin/python3 before the final exec. The engine's own view of its
  # dispositions is the assertion: CPython keeps an inherited SIG_IGN (and
  # prints Handlers.SIG_IGN), installing default_int_handler only when
  # SIGINT was still default at startup; SIGQUIT prints Handlers.SIG_DFL
  # on Python 3.9 and plain 0 on newer Pythons.
  # Forwarding itself is covered by the TERM tests, since a bats launch
  # starts scode asynchronously -- and POSIX forbids a shell from trapping
  # a signal that was ignored on entry, so an INT trap in scode cannot fire
  # under this suite no matter what the launcher does.
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- \
    /usr/bin/python3 -c 'import signal
print("INT:", signal.getsignal(signal.SIGINT))
print("QUIT:", signal.getsignal(signal.SIGQUIT))'
  [ "$status" -eq 0 ]
  [[ "$output" == *"INT: <built-in function default_int_handler>"* ]]
  [[ "$output" != *"SIG_IGN"* ]]
  grep -Eq '^QUIT: (Handlers\.SIG_DFL|0)$' <<< "$output"
  grep -q '"event":"scode_exit"' "$acct"
}

@test "SIGPIPE stays default: a truncated pipeline exits 141" {
  require_runtime_sandbox
  # CPython ignores SIGPIPE at startup, and the launcher runs through
  # CPython: an unrestored disposition would survive into the sandboxed
  # chain, where `yes` would die of a write error (exit 1) instead of the
  # signal (exit 141) -- and coreutils prints the error on stderr.
  run "$SCODE" -C "$TEST_PROJECT" -- /bin/bash -c 'set -o pipefail; yes 2>&1 | head -n 1'
  [ "$status" -eq 141 ]
  [[ "$output" != *"roken pipe"* ]]
}

@test "failed launches past argument validation still record" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- does-not-exist-xyz
  [ "$status" -eq 1 ]
  [ -f "$acct" ]
  grep -q '"exit_code":1' "$acct"
  grep -q '"scratch_kib"' "$acct"
}

@test "help and version produce no record" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" --help
  [ "$status" -eq 0 ]
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" --version
  [ "$status" -eq 0 ]
  : > "$TEST_PROJECT/empty.log"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" audit "$TEST_PROJECT/empty.log"
  [ ! -e "$acct" ]
}

@test "a log writer killed from outside is reported" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  local logf="$TEST_PROJECT/run.log"
  # The engine outlives the writer and exits 0 on its own, and this run
  # delivers no signal of its own -- so the incomplete log must still be
  # reported and the status must not read as success. A blanket
  # suppression of every signal-terminated writer hides this failure,
  # and so does masking every writer death once a handled signal has
  # landed; only a writer death by a signal this run delivered is the
  # interruption.
  # The marker is built at runtime and written to stderr: the log header
  # dumps the command arguments, so a literal marker in the engine string
  # would match before the writer even starts, and stdout never passes
  # through the logger. Only a line the writer itself appended can
  # satisfy the readiness check below.
  SCODE_ACCOUNT_FILE="$acct" "$SCODE" -C "$TEST_PROJECT" --log "$logf" \
    -- /bin/bash -c 'm=writer-; echo "${m}live" >&2; sleep 4; exit 0' \
    2>"$TEST_PROJECT/scode.err" &
  local wrapper_pid=$!
  # writer-live reaches the log only through the writer, so its presence
  # proves the writer is alive and appending; a fixed wait races suite
  # load, where scode can take several seconds to reach the tee spawn.
  local waited=0
  until grep -q 'writer-live' "$logf" 2>/dev/null; do
    sleep 0.25
    waited=$((waited + 1))
    if (( waited > 120 )); then break; fi
  done
  grep -q 'writer-live' "$logf"
  local tee_pid
  tee_pid="$(pgrep -P "$wrapper_pid" -x tee | head -1)"
  [[ -n "$tee_pid" ]]
  kill -TERM "$tee_pid"
  local rc=0
  wait "$wrapper_pid" || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'log writer failed' "$TEST_PROJECT/scode.err"
  grep -q '"exit_code":1' "$acct"
  # The group-signal suppression arm must accept TERM's status too: a
  # supervisor signaling the whole group during the drain grace kills
  # the writer with 143 after the sentinel already proved the log
  # complete, and the documented contract suppresses a terminal-group
  # signal death there, not only INT and HUP. Reaching the arm live
  # means racing the drain window with a group signal, so the rule is
  # pinned by bytes.
  grep -Fq '"$group_signaled" -ne 0 && ( "$tee_rc" -eq 130 || "$tee_rc" -eq 143 || "$tee_rc" -eq 129 )' "$SCODE_SOURCE"
}

@test "a forwarded TERM that the engine handles keeps the log complete" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  local logf="$TEST_PROJECT/run.log"
  # The engine traps TERM, writes a shutdown diagnostic to stderr, and
  # exits 0. The writer must live as long as the engine does: killing it
  # at the forward made the run report success with an incomplete log,
  # the diagnostic lost to a broken pipe. Markers are built at runtime
  # and written to stderr so only writer-appended lines can match them.
  SCODE_ACCOUNT_FILE="$acct" "$SCODE" -C "$TEST_PROJECT" --log "$logf" \
    -- /bin/bash -c 'trap "d=dia-; echo \"\${d}gnostic\" >&2; exit 0" TERM; m=ready-; echo "${m}now" >&2; while :; do sleep 1; done # scode-term-handle-marker' \
    2>"$TEST_PROJECT/scode.err" &
  local wrapper_pid=$!
  local waited=0
  until grep -q 'ready-now' "$logf" 2>/dev/null; do
    sleep 0.25
    waited=$((waited + 1))
    if (( waited > 120 )); then break; fi
  done
  grep -q 'ready-now' "$logf"
  local tpgid pgid
  tpgid="$(ps -o tpgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  pgid="$(ps -o pgid= -p "$wrapper_pid" | tr -d '[:space:]')"
  if [[ -n "$tpgid" && "$tpgid" == "$pgid" ]]; then
    # Group-signal environment: the TERM would never be forwarded and this
    # engine loops forever, so nothing would ever exit. Stop the run and
    # the engine, then skip; the group path is covered by the pty test.
    kill -TERM "$wrapper_pid" 2>/dev/null || true
    local w=0
    while kill -0 "$wrapper_pid" 2>/dev/null && (( w < 10 )); do sleep 0.5; w=$(( w + 1 )); done
    kill -KILL "$wrapper_pid" 2>/dev/null || true
    wait "$wrapper_pid" 2>/dev/null || true
    pkill -f scode-term-handle-marker 2>/dev/null || true
    skip "scode is the terminal's foreground group; the group path absorbs the TERM"
  fi
  kill -TERM "$wrapper_pid"
  local rc=0
  wait "$wrapper_pid" || rc=$?
  [ "$rc" -eq 0 ]
  grep -q 'dia-gnostic' "$logf"
  grep -q '"exit_code":0' "$acct"
}

@test "the log ends with the completion marker on a normal run" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  local logf="$TEST_PROJECT/run.log"
  # scode appends a sentinel as the last line it puts in the pipe after
  # the engine is reaped. Its presence is the proof the run's own
  # teardown uses that the writer drained the engine's stderr before it
  # was allowed to finish, and it marks the log complete for consumers.
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" --log "$logf" \
    -- /bin/bash -c 'm=out-; echo "${m}put-line" >&2; exit 0'
  [ "$status" -eq 0 ]
  grep -q 'out-put-line' "$logf"
  grep -q 'scode-log-complete' "$logf"
  # The token must draw from the OS randomness source. bash 3.2, the
  # macOS /bin/bash, seeds RANDOM from the pid and the clock, and the
  # launch chain execs without forking, so the sandboxed command knows
  # scode's pid exactly; a RANDOM-only token would be brute-forceable
  # from inside the sandbox.
  grep -q 'od -An -N12 -tx1 /dev/urandom' "$SCODE_SOURCE"
}

@test "the launcher hands the engine the caller's locale" {
  # CPython rewrites a C locale at startup (PEP 538): with LC_ALL absent
  # and LC_CTYPE C, it sets LC_CTYPE=C.UTF-8 in its own environment, and
  # the launcher's exec would hand that rewrite to the engine -- wc -m
  # counts one character where the caller's C locale counts two bytes.
  # The launcher chain captures the locale variables and the interpreter
  # puts them back before the exec; this pins that restore on the
  # python3 branch every supported host takes.
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run env -u LC_ALL LC_CTYPE=C LANG=C \
    "$SCODE" -C "$TEST_PROJECT" -- /bin/bash -c 'printf "\303\251" | wc -m'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*2[[:space:]]*$')" -eq 1 ]
  # A non-C caller locale must survive the same path: the restore must
  # never replace a set variable with a different value. The locale name
  # differs between hosts, so pick one the host actually has.
  local utf
  utf="$(locale -a 2>/dev/null | grep -iE '^(C[.]utf-?8|en_US[.]utf-?8)$' | head -1)" || true
  if [[ -n "$utf" ]]; then
    SCODE_ACCOUNT_FILE="$acct" run env LC_ALL="$utf" \
      "$SCODE" -C "$TEST_PROJECT" -- /bin/bash -c 'printf "\303\251" | wc -m'
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -cE '^[[:space:]]*1[[:space:]]*$')" -eq 1 ]
  fi
}

@test "the launcher hands the engine the caller's compiler environment" {
  # The xcrun shim behind /usr/bin/python3 injects SDKROOT, CPATH, and
  # LIBRARY_PATH when the caller left them unset, and the launcher exec
  # would hand that injection to the engine -- an iOS-targeted Clang
  # would silently receive the macOS SDK as -isysroot. The carrier
  # dance restores the exact caller state; this pins it on the python3
  # branch every supported host takes.
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run env -u SDKROOT -u CPATH -u LIBRARY_PATH \
    "$SCODE" -C "$TEST_PROJECT" -- /bin/sh -c 'printf "markers[%s]\n" "${SDKROOT+1}${CPATH+1}${LIBRARY_PATH+1}"'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cF 'markers[]')" -eq 1 ]
  SCODE_ACCOUNT_FILE="$acct" run env SDKROOT=/sdk CPATH=/inc LIBRARY_PATH=/lib \
    "$SCODE" -C "$TEST_PROJECT" -- /bin/sh -c 'printf "markers[%s]\n" "${SDKROOT+1}${CPATH+1}${LIBRARY_PATH+1}"'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cF 'markers[111]')" -eq 1 ]
}

@test "the accounting bound counts bytes, not characters" {
  # The single-append guarantee is a write-size guarantee: a record
  # over 800 bytes splits across stdio writes, and concurrent writers
  # can interleave the fragments. A multibyte path or id can stay under
  # a character count while over the byte count, so the check sizes the
  # record in bytes and treats an unmeasurable record as over the
  # bound. macOS scratch paths are host-generated ASCII and the id is
  # capped at 128 characters, so no reachable run builds a record that
  # distinguishes the two counts on this host; the boundary is pinned
  # at the source instead.
  [ "$(grep -cF 'wc -c | tr -d " ")" || _nb=999999' "$SCODE_SOURCE")" -eq 2 ]
  [ "$(grep -cF '(( _nb > 800 ))' "$SCODE_SOURCE")" -eq 2 ]
  [ "$(grep -cF '${#_record} > 800' "$SCODE_SOURCE")" -eq 0 ]
}

@test "an inherited pending-int file name is left alone on early exits" {
  # The EXIT trap cleans up the pending-INT file by name. Both it and the
  # accounting arming flag live in the environment's namespace, so scode
  # must start every run with them empty: an exported
  # _SCODE_PENDING_INT_FILE must not have the trap delete that file, and
  # an exported _SCODE_ACCOUNT_ARMED must not make an early exit record.
  local sentinel="$TEST_PROJECT/sentinel"
  printf 'keep\n' > "$sentinel"
  local acct="$TEST_PROJECT/account.jsonl"
  run env _SCODE_PENDING_INT_FILE="$sentinel" _SCODE_ACCOUNT_ARMED=1 \
    _SCODE_ACCOUNT_FILE="$acct" "$SCODE" --help
  [ "$status" -eq 0 ]
  grep -q 'keep' "$sentinel"
  [ ! -e "$acct" ]
  # The trap-time record writes through fd 7, and its documented degrade
  # on a failed creation is a silent write failure. scode must therefore
  # close fd 7 at startup: a descriptor the caller happened to hold open
  # there would receive the record instead. Forcing a failed creation
  # live is not practical, so the posture is pinned by bytes.
  grep -Fq '{ exec 7>&-; } 2>/dev/null || true' "$SCODE_SOURCE"
}

@test "relative SCODE_ACCOUNT_FILE resolves against the invoking directory" {
  require_runtime_sandbox
  local invoke_dir
  invoke_dir="$(mktemp -d)"
  track_cleanup "$invoke_dir"
  local prev_dir="$PWD"
  cd "$invoke_dir"
  SCODE_ACCOUNT_FILE="account-rel.jsonl" run "$SCODE" -C "$TEST_PROJECT" -- true
  local rc=$status
  cd "$prev_dir"
  [ "$rc" -eq 0 ]
  [ -f "$invoke_dir/account-rel.jsonl" ]
  [ ! -e "$TEST_PROJECT/account-rel.jsonl" ]
}

@test "account id characters outside the supported set are dropped, not mangled" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" SCODE_ACCOUNT_ID="job 42" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  grep -q '"account_id":null' "$acct"
}

@test "account id longer than 128 characters is dropped; 128 is kept" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  local long_id keep_id
  printf -v long_id 'a%.0s' {1..129}
  SCODE_ACCOUNT_FILE="$acct" SCODE_ACCOUNT_ID="$long_id" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  grep -q '"account_id":null' "$acct"
  # A 128-character id survives whole -- the cap drops, never truncates --
  # and both records stay single valid lines. The trailing z proves the
  # last character made it: a truncated id would fail the grep below.
  # (Brace expansion inside the same word would splice the z onto the
  # final element, so it is appended afterward.)
  printf -v keep_id 'b%.0s' {1..127}
  keep_id="${keep_id}z"
  SCODE_ACCOUNT_FILE="$acct" SCODE_ACCOUNT_ID="$keep_id" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$acct")" -eq 2 ]
  grep -Fq "\"account_id\":\"$keep_id\"" "$acct"
}

@test "dry run records no_scratch" {
  # Platform-neutral: a dry run never attempts a launch, so the record
  # carries the default reason on both platforms.
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" --dry-run -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ -f "$acct" ]
  grep -q '"scratch_kib":null' "$acct"
  grep -q '"reason":"no_scratch"' "$acct"
}

@test "project-local python modules do not execute before the sandbox" {
  require_runtime_sandbox
  local acct="$TEST_PROJECT/account.jsonl"
  # With -c, CPython puts the current directory first on sys.path, and the
  # launcher runs inside the project: a planted signal.py or enum.py would
  # execute with full host privileges before the sandbox starts, unless
  # the launcher uses isolated mode (-I). The poison exits 9, so shadowing
  # is impossible to miss.
  printf 'import sys\nsys.exit(9)\n' > "$TEST_PROJECT/signal.py"
  printf 'import sys\nsys.exit(9)\n' > "$TEST_PROJECT/enum.py"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$acct")" -eq 1 ]
}

@test "Linux records tmpfs_unmeasurable for runs that reached the launch stage" {
  [[ "$(uname -s)" == "Linux" ]] || skip "Linux only"
  # The host must be able to form the bwrap namespace, or no run reaches
  # the launch stage at all.
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  bwrap --ro-bind / / --unshare-all /bin/true >/dev/null 2>&1 \
    || skip "user namespaces unavailable"
  local acct="$TEST_PROJECT/account.jsonl"
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  grep -q '"scratch_kib":null' "$acct"
  grep -q '"reason":"tmpfs_unmeasurable"' "$acct"
}

@test "concurrent runs sharing one sink each append one intact record" {
  require_runtime_sandbox
  [[ -x /usr/bin/python3 ]] || skip "/usr/bin/python3 is required"
  local acct="$TEST_PROJECT/account.jsonl"
  # The record is one append bounded below stdio's 1024-byte flush unit, so
  # four runs appending to the same sink must interleave whole lines even
  # though the appends are unsynchronized.
  local i
  local pids=()
  for i in 1 2 3 4; do
    SCODE_ACCOUNT_FILE="$acct" SCODE_ACCOUNT_ID="par-$i" \
      "$SCODE" -C "$TEST_PROJECT" -- true &
    pids+=("$!")
  done
  for i in 1 2 3 4; do
    wait "${pids[$(( i - 1 ))]}" || return 1
  done
  [ "$(wc -l < "$acct")" -eq 4 ]
  /usr/bin/python3 - "$acct" <<'PY'
import json, sys
ids = []
for line in open(sys.argv[1]):
    rec = json.loads(line)
    assert rec["event"] == "scode_exit", rec
    ids.append(rec["account_id"])
assert sorted(ids) == ["par-1", "par-2", "par-3", "par-4"], ids
PY
}

@test "an accounting append failure is reported and leaves the run's status alone" {
  require_runtime_sandbox
  command -v hdiutil >/dev/null 2>&1 || skip "hdiutil not installed"
  # A genuinely full filesystem is the honest way to make the append
  # fail. A nonzero file-size limit never trips on macOS: a single
  # write is cut at the limit value, and scode's record is far smaller
  # than any workable quota. The sink is created before the volume is
  # filled, so the append's open succeeds and only the write itself can
  # fail. The failure used to vanish silently: no warning, suppressed
  # status -- and a fragment without its newline would join onto the
  # next run's record as one corrupt line.
  #
  # The volume is FAT32, not APFS: APFS's copy-on-write metadata can
  # free blocks between the fill and the append -- a volume that refused
  # a one-byte write accepted the ~250-byte record a second later,
  # three runs in ten. FAT32 has nothing to reclaim, so the refusal
  # holds for as long as the test needs it (verified 3/3 with a 2 s
  # gap); the msdos driver reports the full volume as EINVAL, which
  # fails the append's printf exactly like ENOSPC would.
  local dmg="$TEST_PROJECT/full.dmg"
  local mnt="$TEST_PROJECT/mnt"
  local acct="$mnt/account.jsonl"
  hdiutil create -size 40m -fs FAT32 -volname scode-enospc "$dmg" >/dev/null 2>&1 \
    || skip "could not create the disk image"
  # -mountpoint does not create the directory on every hdiutil version.
  mkdir -p "$mnt"
  if ! hdiutil attach "$dmg" -quiet -mountpoint "$mnt" -nobrowse >/dev/null 2>&1; then
    skip "could not attach the disk image"
  fi
  _SCODE_TEST_MOUNT="$mnt"
  : > "$acct"
  if ! /usr/bin/python3 - "$acct" <<'PY'
import os, sys
f = open(sys.argv[1], "ab")
for size in (65536, 128):
    try:
        while True:
            f.write(b"x" * size)
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass
# Fill down to the last byte. Scoping the refusal to the record's
# 800-byte bound is not enough: the record itself is far smaller, so a
# volume that refuses 801 bytes can still accept it. Every write is
# fsynced, so APFS cannot park it in the page cache; the loop ends when
# even one byte fails.
try:
    while True:
        f.write(b"y")
        f.flush()
        os.fsync(f.fileno())
except OSError:
    pass
# One more byte must still fail; if it lands, the filler did not reach
# a full volume and the test skips rather than assert against slack.
try:
    f.write(b"y")
    f.flush()
    os.fsync(f.fileno())
    sys.exit(3)
except OSError:
    pass
# The buffer may still hold unflushable bytes; the close-time flush
# raises the same ENOSPC and must not fail the filler.
try:
    f.close()
except OSError:
    pass
sys.exit(0)
PY
  then
    skip "could not fill the disk image"
  fi
  SCODE_ACCOUNT_FILE="$acct" run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"accounting append failed"* ]]
  # The sink is the volume-filling file itself, so it is anything but
  # empty. What must hold is the corruption contract: a consumer parsing
  # the sink line by line finds no parsable record from this run -- the
  # failed write left nothing, or a fragment the failed seal may or may
  # not have terminated. Asserted before teardown detaches the image,
  # which removes the path and would make any existence check vacuous.
  if /usr/bin/python3 -c 'import json, sys
lines = [ln for ln in open(sys.argv[1]) if ln.strip()]
json.loads(lines[-1])' "$acct" 2>/dev/null; then
    echo "a record landed despite the full volume" >&2
    false
  fi
}
