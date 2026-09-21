#!/usr/bin/env bash
# Shared helpers for scode test suite

SCODE_SOURCE="$BATS_TEST_DIRNAME/../scode"
SCODE="${SCODE_UNDER_TEST:-$SCODE_SOURCE}"
NO_SANDBOX_JS="$BATS_TEST_DIRNAME/../lib/no-sandbox.js"

# Use a real temp dir as the project directory so path validation passes
setup() {
  TEST_PROJECT="$(mktemp -d)"
  _EXTRA_CLEANUP_DIRS=()
  unset SCODE_CONFIG
  unset SCODE_NET
  unset SCODE_FS_MODE
  unset SCODE_ACCOUNT_FILE
  unset SCODE_ACCOUNT_ID
}

teardown() {
  # A test that mounted a disk image (see the ENOSPC accounting test)
  # must have it detached before the project directory is removed. A
  # detach can fail while a process still holds the volume open, so it
  # is retried before giving up. If it never succeeds, the backing
  # files must survive: deleting the image under a mounted volume
  # corrupts unrelated I/O, so the project directory is left in place
  # and the failure is reported loudly instead of being swallowed.
  local _mounted=0 _detach_ok=0 _try
  if [[ -n "${_SCODE_TEST_MOUNT:-}" ]]; then
    _mounted=1
    for _try in 1 2 3; do
      if hdiutil detach "$_SCODE_TEST_MOUNT" -quiet >/dev/null 2>&1; then
        _detach_ok=1
        break
      fi
      sleep 2
    done
  fi
  if [[ "$_mounted" -eq 1 && "$_detach_ok" -eq 0 ]]; then
    echo "teardown: could not detach $_SCODE_TEST_MOUNT; leaving it mounted and leaving $TEST_PROJECT (its backing files) in place" >&2
    return 1
  fi
  _SCODE_TEST_MOUNT=""
  rm -rf "$TEST_PROJECT"
  for _dir in "${_EXTRA_CLEANUP_DIRS[@]}"; do
    rm -rf "$_dir"
  done
}

# Register a directory for cleanup in teardown (safe even on test failure)
track_cleanup() {
  _EXTRA_CLEANUP_DIRS+=("$1")
}

require_node() {
  command -v node >/dev/null 2>&1 || skip "node not installed"
}

# Some preload tests exercise rewriting through a wrapper binary such as
# `timeout` or `stdbuf`. These ship with GNU coreutils and are absent on stock
# macOS, so the behavior can only be asserted where the wrapper actually exists.
require_command() {
  command -v "$1" >/dev/null 2>&1 || skip "$1 not installed"
}

# Like require_command, but ignores shell builtins and keywords. `time` is a
# Bash keyword, so `command -v time` succeeds even where /usr/bin/time is not
# installed -- and the preload can only rewrite a real executable.
require_external_binary() {
  local name="$1" dir
  local IFS=:
  for dir in $PATH; do
    [[ -x "${dir}/${name}" ]] && return 0
  done
  skip "${name} binary not installed"
}

# bubblewrap can be installed yet unusable: Ubuntu 24.04 confines unprivileged
# user namespaces through AppArmor, and most containers block them outright.
# Probe an actual sandbox rather than trusting that the binary exists.
require_linux_bwrap() {
  [[ "$(uname -s)" != "Linux" ]] && skip "linux only"
  command -v bwrap >/dev/null 2>&1 || skip "bwrap not installed"
  bwrap --ro-bind / / --dev /dev --proc /proc -- /bin/true >/dev/null 2>&1 \
    || skip "bubblewrap cannot create a sandbox in this environment"
}

# ---------- Platform-aware dry-run assertions ----------
#
# The dry-run rendering differs by platform: macOS prints an SBPL profile, Linux
# prints the bubblewrap argv. These helpers assert the intended behavior so one
# test covers both platforms instead of hardcoding one platform's syntax.

# Linux renders the argv shell-quoted, so a path containing spaces or a hash
# appears escaped. Accept either rendering.
assert_output_has_path() {
  local output="$1" path="$2" escaped
  escaped="$(printf '%q' "$path")"
  [[ "$output" == *"$path"* || "$output" == *"$escaped"* ]]
}

assert_dry_run_command() {
  local output="$1" command_word="$2"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    [[ "$output" == *"# Command: $command_word"* ]]
  else
    [[ "$output" == *" -- $command_word"* ]]
  fi
}

# Strict/non-strict and project read-write assertions already exist further down
# as assert_strict_mode_output, assert_non_strict_mode_output, and
# assert_project_read_write_output. Use those.

dry_run_cmd() {
  "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

# Some tests require launching an actual sandboxed command (not just dry-run).
# In restricted CI/sandbox environments, nested sandbox-exec can fail; skip those.
require_runtime_sandbox() {
  [[ "$(uname -s)" != "Darwin" ]] && skip "macOS only"

  # If sandbox-exec itself cannot run, this host cannot run runtime tests.
  /usr/bin/sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1 \
    || skip "runtime sandbox unavailable in this environment"

  # If the host sandbox works but scode probe fails, fail the test.
  run "$SCODE" -C "$TEST_PROJECT" -- true
  [ "$status" -eq 0 ]
}

require_any_runtime_sandbox() {
  case "$(uname -s)" in
    Darwin)
      require_runtime_sandbox
      ;;
    Linux)
      [[ -x /usr/bin/bwrap ]] || skip "bubblewrap unavailable"
      /usr/bin/bwrap --ro-bind / / --dev /dev --proc /proc -- /usr/bin/true >/dev/null 2>&1 \
        || skip "runtime sandbox unavailable in this environment"
      run "$SCODE" -C "$TEST_PROJECT" -- true
      [ "$status" -eq 0 ]
      ;;
    *)
      skip "runtime sandbox unsupported on this platform"
      ;;
  esac
}

linux_dry_run() {
  _SCODE_PLATFORM=linux "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

darwin_dry_run() {
  _SCODE_PLATFORM=darwin "$SCODE" --dry-run -C "$TEST_PROJECT" -- "$@"
}

assert_dry_run_generated() {
  local out="$1"
  [[ "$out" == *"(version 1)"* || "$out" == *"bwrap --new-session"* ]]
}

assert_network_disabled_output() {
  local out="$1"
  [[ "$out" == *"(deny network"* || \
     "$out" == *"--unshare-net"* || \
     ( "$out" == *"(deny default)"* && "$out" != *"(allow network"* ) ]]
}

assert_network_enabled_output() {
  local out="$1"
  [[ "$out" != *"(deny network"* ]]
  [[ "$out" != *"--unshare-net"* ]]
}

assert_project_read_only_output() {
  local out="$1"
  local project_dir="$2"
  local project_real
  project_real="$(cd "$project_dir" && pwd -P)"
  [[ "$out" == *"(deny file-write*"* || \
     ( "$out" == *"Project directory (read-only)"* && "$out" == *"(subpath \"${project_real}\")"* ) || \
     "$out" == *"--ro-bind ${project_dir} ${project_dir}"* || \
     "$out" == *"--ro-bind ${project_real} ${project_real}"* ]]
}

assert_project_read_write_output() {
  local out="$1"
  local project_dir="$2"
  local project_real
  project_real="$(cd "$project_dir" && pwd -P)"
  [[ "$out" != *"(deny file-write*"* ]]
  [[ "$out" != *"--ro-bind ${project_dir} ${project_dir}"* ]]
  [[ "$out" != *"--ro-bind ${project_real} ${project_real}"* ]]
}

assert_strict_mode_output() {
  local out="$1"
  [[ "$out" == *"(deny default)"* || "$out" == *"# Mode: strict"* ]]
}

assert_non_strict_mode_output() {
  local out="$1"
  [[ "$out" != *"(deny default)"* ]]
  [[ "$out" != *"# Mode: strict"* ]]
}

# Emit the pty INT harness used by the accounting signal tests.
# MODE=group writes ^C to the pty (a group INT); MODE=pid kills scode's
# pid directly; MODE=timed kills scode's pid SEND_AFTER seconds after
# spawn; MODE=onstring kills scode's pid as soon as TRIGGER (default:
# scode's unknown-harness warning, printed after the traps arm and long
# before the launch) appears in the output -- a deterministic mid-startup
# arrival; MODE=early writes ^C to the pty immediately after spawn.
# MODE=groupterm sends SIGTERM to the pty's foreground group.
# EXTRA_ARGS carries extra scode arguments (e.g. --log FILE). Prints
# plain fact lines the tests assert on.
write_pty_int_harness() {
  cat > "$1" <<'PY'
import os, pty, re, select, shlex, signal, sys, time

scode = os.environ["SCODE"]
proj = os.environ["PROJ"]
acct = os.environ["ACCT"]
mode = os.environ.get("MODE", "group")
# SLEEP scales the default engine's lifetime; INNER replaces the engine
# script outright (e.g. a handler that continues instead of exiting);
# MARKER is the output token counted as one handler delivery.
sleep_secs = os.environ.get("SLEEP", "30")
inner = os.environ.get(
    "INNER",
    "trap 'echo handled-int; exit 0' INT; echo engine-ready; sleep %s & wait $!" % sleep_secs,
)
marker = os.environ.get("MARKER", "handled-int")
extra = shlex.split(os.environ.get("EXTRA_ARGS", ""))
if os.path.exists(acct):
    os.remove(acct)
env = dict(os.environ)
env["SCODE_ACCOUNT_FILE"] = acct


def record_ready():
    # The sink file is created when accounting arms, long before the run
    # ends, and stays empty until the exit trap writes the record. An
    # empty file means the run is still going; only content says done.
    try:
        return os.path.getsize(acct) > 0
    except OSError:
        return False


def drain_once(fd, out):
    # scode is a session leader: while it exits, the kernel holds it in
    # its exit path until the terminal's output queue drains. A reader
    # that stops reading parks scode there forever, past SIGKILL, so
    # the harness keeps reading until the child is reaped.
    try:
        r, _, _ = select.select([fd], [], [], 0.05)
    except OSError:
        return True
    if not r:
        return False
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        return True
    if chunk:
        out.extend(chunk)
        return False
    return True


def reap_child(pid, fd, out, seconds):
    # A bounded reap that drains the terminal while it waits, so the
    # child's exit path never waits on a reader that stopped.
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        wpid, wstatus = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            return wstatus
        drain_once(fd, out)
        time.sleep(0.01)
    return None


pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.environ.clear(); os.environ.update(env)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    os.execvp(scode, [scode, "-C", proj] + extra + ["--", "/bin/bash", "-c", inner])
    os._exit(127)

out = bytearray()
sent_at = None
started = time.monotonic()
if mode == "early":
    # ^C during scode's own startup, before any handler exists.
    os.write(fd, b"\x03")
    sent_at = time.monotonic()
deadline = time.monotonic() + float(os.environ.get("DEADLINE", str(float(sleep_secs) + 10)))
while time.monotonic() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    if mode in ("group", "pid", "groupterm") and sent_at is None and b"engine-ready" in out:
        if mode == "group":
            os.write(fd, b"\x03")
        elif mode == "groupterm":
            # A group TERM cannot be typed; signal the pty's foreground
            # group the way a supervisor would.
            os.kill(-pid, signal.SIGTERM)
        else:
            os.kill(pid, signal.SIGINT)
        sent_at = time.monotonic()
    if mode == "timed" and sent_at is None and time.monotonic() - started > float(os.environ.get("SEND_AFTER", "0.12")):
        os.kill(pid, signal.SIGINT)
        sent_at = time.monotonic()
    if mode == "onstring" and sent_at is None:
        trigger = os.environ.get("TRIGGER", "not a known harness").encode()
        if trigger in out:
            os.kill(pid, signal.SIGINT)
            sent_at = time.monotonic()
    if sent_at is not None and record_ready():
        break
if sent_at is None:
    print("engine never became ready")
    # Stop the child here instead of leaving the engine running past
    # the harness, and reap it through the draining path: a killed
    # session leader still cannot finish exiting with output pending.
    os.kill(pid, signal.SIGKILL)
    reap_child(pid, fd, out, 10)
    sys.exit(1)
# A regression can leave the engine alive past cancellation; a blocking
# waitpid here would hang the whole suite long after the harness
# deadline. Bound the wait, then force the issue so no engine outlives
# the test. Both waits keep draining the terminal: scode's exit path
# waits for the output queue to drain, and SIGKILL does not interrupt
# that wait.
status = reap_child(pid, fd, out, 10)
if status is None:
    print("engine did not exit; killing")
    os.kill(pid, signal.SIGKILL)
    status = reap_child(pid, fd, out, 10)
if status is None:
    print("could not reap scode even after SIGKILL and draining")
    sys.exit(1)
rc = os.waitstatus_to_exitcode(status)
recorded_at = time.monotonic()
time.sleep(0.3)
record = open(acct).read() if os.path.exists(acct) else ""
text = out.decode(errors="replace")
m = re.search(r'"scratch_path":"([^"]*)"', record)
scratch = m.group(1) if m else None
print("mode: %s" % mode)
print("rc: %s" % rc)
print("handler fires: %d" % text.count(marker))
print("forward-warning: %s" % ("yes" if "not forwarding" in text else "no"))
# engine-ready is printed by the engine as soon as it starts; the
# handler marker only appears when the signal handler fires. A stub that
# launches and then dies by the signal must read as launched.
print("engine seen: %s" % ("yes" if "engine-ready" in text else "no"))
print("signal-to-record s: %.1f" % (recorded_at - sent_at))
m_rc = re.search(r'"exit_code":([0-9]+)', record)
print("record exit_code: %s" % (m_rc.group(1) if m_rc else "none"))
print("scratch torn down: %s" % (scratch is None or not os.path.exists(scratch)))

PY
}
