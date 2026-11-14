"""Identify a Seatbelt run by two existing probe files; signal by PID version.

Darwin ABI: xnu/bsd/sys/proc_info_private.h (PROC_PIDUNIQIDENTIFIERINFO)
and libsyscall/wrappers/libproc/libproc.c (proc_signal_with_audittoken).
No process name, environment variable, parent PID, or process group is identity.
"""

import ctypes as C
import errno
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

PROC_ALL_PIDS = 1
PROC_PIDUNIQIDENTIFIERINFO = 17
SANDBOX_FILTER_PATH = 1
TERM_SECONDS = 1.0
KILL_SECONDS = 1.0
SCAN_SECONDS = 0.05
AuditToken = C.c_uint32 * 8


class UniqueInfo(C.Structure):
    _fields_ = [("uuid", C.c_uint8 * 16), ("unique", C.c_uint64),
                ("parent", C.c_uint64), ("version", C.c_int32),
                ("parent_version", C.c_int32), ("reserved", C.c_uint64 * 2)]


class Darwin:
    def __init__(self):
        self.proc = C.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        self.sandbox = C.CDLL('/usr/lib/libsandbox.1.dylib', use_errno=True)
        self.check = self.sandbox.sandbox_check
        self.check.argtypes = [C.c_int, C.c_char_p, C.c_int]
        self.check.restype = C.c_int
        self.proc.proc_pidinfo.argtypes = [C.c_int, C.c_int, C.c_uint64,
                                          C.c_void_p, C.c_int]
        self.proc.proc_listpids.argtypes = [C.c_uint32, C.c_uint32,
                                           C.c_void_p, C.c_int]
        # XNU libproc.c declares audit_token_t * (not a by-value token).
        # This pointer ABI applies to both arm64 and x86_64.
        self.proc.proc_signal_with_audittoken.argtypes = [C.POINTER(AuditToken), C.c_int]
        self.proc.proc_signal_with_audittoken.restype = C.c_int

    def token(self, pid):
        info = UniqueInfo()
        if self.proc.proc_pidinfo(pid, PROC_PIDUNIQIDENTIFIERINFO, 0,
                                  C.byref(info), C.sizeof(info)) != C.sizeof(info):
            return None
        # The signal syscall uses PID and idversion from the audit token.
        token = AuditToken()
        token[5], token[7] = pid, info.version
        return token

    def pids(self):
        size = self.proc.proc_listpids(PROC_ALL_PIDS, 0, None, 0)
        if size <= 0:
            raise RuntimeError('cannot enumerate processes')
        while True:
            buf = (C.c_int * (size // C.sizeof(C.c_int) + 128))()
            used = self.proc.proc_listpids(PROC_ALL_PIDS, 0, buf, C.sizeof(buf))
            if used <= 0:
                raise RuntimeError('cannot enumerate processes')
            if used < C.sizeof(buf):
                return [pid for pid in buf[:used // C.sizeof(C.c_int)] if pid > 0]
            size = C.sizeof(buf) * 2

    def fingerprint(self, pid, directory):
        return tuple(self.check(pid, b'file-read-data', SANDBOX_FILTER_PATH,
                                C.c_char_p(os.fsencode(directory / name)))
                     for name in ('deny', 'allow'))

    def members(self, directory):
        for pid in self.pids():
            before = self.token(pid)
            if before is None or self.fingerprint(pid, directory) != (1, 0):
                continue
            after = self.token(pid)
            if after is not None and bytes(before) == bytes(after):
                yield before

    def send(self, token, sig):
        result = self.proc.proc_signal_with_audittoken(C.byref(token), sig)
        if result not in (0, errno.ESRCH):
            raise OSError(result, 'generation-checked signal failed')


def profile(directory):
    # Generated paths still need escaping: the caller's temp root may contain
    # quotes. Never interpolate raw path text as SBPL syntax.
    escaped = str(directory).replace('\\', '\\\\').replace('"', '\\"')
    return ('\n; Per-run strict teardown identity (protected existing files)\n'
            f'(deny file-write* (subpath "{escaped}"))\n'
            f'(deny file-read* (literal "{escaped}/deny"))\n'
            f'(allow file-read* (literal "{escaped}/allow"))\n')


def prepare(api, directory):
    for name in ('deny', 'allow'):
        (directory / name).touch(mode=0o600, exist_ok=False)
    probe = subprocess.Popen(['/usr/bin/sandbox-exec', '-p',
                              '(version 1)(allow default)' + profile(directory),
                              '/bin/sleep', '10'], close_fds=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if api.fingerprint(probe.pid, directory) == (1, 0):
                break
            time.sleep(SCAN_SECONDS)
        else:
            raise RuntimeError('sandbox_check cannot identify the probe')
        if api.fingerprint(os.getpid(), directory) != (0, 0):
            raise RuntimeError('sandbox_check cannot exclude the parent')
        token = api.token(probe.pid)
        if token is None or not any(bytes(t) == bytes(token) for t in api.members(directory)):
            raise RuntimeError('cannot identify the probe process generation')
        # Verify the kernel rejects a stale generation without delivering TERM.
        stale = AuditToken.from_buffer_copy(token)
        stale[7] ^= 0x80000000
        if api.proc.proc_signal_with_audittoken(C.byref(stale), signal.SIGTERM) != errno.ESRCH:
            raise RuntimeError('kernel does not reject stale process generations')
        if probe.poll() is not None:
            raise RuntimeError('stale process generation signaled the probe')
        # ESRCH is acceptable during cleanup races, but must never make this
        # ABI self-check pass. This SPI requires a real signal (not signal 0).
        if api.proc.proc_signal_with_audittoken(C.byref(token), signal.SIGTERM) != 0:
            raise RuntimeError('live process generation was rejected')
        if probe.wait(timeout=2) != -signal.SIGTERM:
            raise RuntimeError('generation-checked TERM did not stop the probe')
    finally:
        if probe.poll() is None:
            probe.kill()
        probe.wait()
    print(profile(directory))


def cleanup(api, directory):
    if api.fingerprint(os.getpid(), directory) != (0, 0):
        raise RuntimeError('marker files or sandbox_check are no longer usable')
    # Rescan through the grace period: a TERM handler may fork another child.
    failures = {}
    for sig, seconds in ((signal.SIGTERM, TERM_SECONDS), (signal.SIGKILL, KILL_SECONDS)):
        sent = set()
        deadline = time.monotonic() + seconds
        while True:
            members = list(api.members(directory))
            if not members:
                break
            for token in members:
                identity = bytes(token)
                if sig == signal.SIGTERM and identity in sent:
                    continue
                try:
                    api.send(token, sig)
                except OSError as exc:
                    # One member may have changed credentials. Retain its
                    # error, but still signal others and attempt escalation.
                    code = errno.errorcode.get(exc.errno, str(exc.errno))
                    failures[identity, sig] = (
                        f'PID {token[5]} generation {token[7]} '
                        f'{signal.Signals(sig).name}: {code} ({exc})')
                sent.add(identity)
            if time.monotonic() >= deadline:
                break
            time.sleep(SCAN_SECONDS)
        if not members:
            break
    problems = list(failures.values())
    if list(api.members(directory)):
        problems.append('sandbox members remain after SIGKILL')
    if problems:
        raise RuntimeError('; '.join(problems))


def main():
    try:
        if len(sys.argv) != 3:
            raise ValueError('expected prepare|cleanup and a marker directory')
        mode, raw_directory = sys.argv[1:]
        if mode not in ('prepare', 'cleanup'):
            raise ValueError('unknown teardown operation')
        directory = Path(raw_directory).resolve()
        api = Darwin()
        if mode == 'prepare':
            prepare(api, directory)
        elif mode == 'cleanup':
            cleanup(api, directory)
    except (OSError, RuntimeError, AttributeError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f'scode: strict descendant teardown unavailable: {exc}; '
              'detached descendants may survive', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
