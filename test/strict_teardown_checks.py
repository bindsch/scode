"""Deterministic regressions for fixture readiness and teardown self-checks."""
import contextlib
import errno
import importlib.util
import io
import itertools
from pathlib import Path
import sys
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pidfile():
    fixture = load('fixture', Path(__file__).with_name('strict_descendant.py'))
    # Force the exact race without scheduling a daemon repeatedly.
    with patch.object(Path, 'read_text', side_effect=[FileNotFoundError(), '', '123']), \
            patch.object(fixture.time, 'sleep') as sleep:
        result = fixture.wait_for(lambda: fixture.read_pid('unused'), 'not ready')
        assert result == 123
        assert sleep.call_count == 2
    print('pidfile: missing and empty reads wait; complete content returns PID')


def probe():
    helper = load('helper', Path(__file__).parent.parent / 'lib/strict-teardown.py')
    api = Mock()
    token = helper.AuditToken()
    token[5], token[7] = 123, 456
    api.fingerprint.side_effect = [(1, 0), (0, 0)]
    api.token.return_value = token
    api.members.return_value = [token]
    api.proc.proc_signal_with_audittoken.return_value = errno.ESRCH
    process = Mock(pid=123)
    process.poll.return_value = None
    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(Path, 'touch'))
        stack.enter_context(patch.object(helper.subprocess, 'Popen', return_value=process))
        try:
            helper.prepare(api, Path('/unused'))
        except RuntimeError as exc:
            assert str(exc) == 'live process generation was rejected', str(exc)
        else:
            raise AssertionError('probe accepted an unusable live token')
    api.send.assert_not_called()
    process.kill.assert_called_once()
    process.wait.assert_called_once()
    print('probe: stale ESRCH alone cannot pass; live token must work')


def signal_errors():
    helper = load('helper', Path(__file__).parent.parent / 'lib/strict-teardown.py')
    # Exercise the real errno handling without signaling real processes.
    for rejected in ((helper.signal.SIGTERM,), (helper.signal.SIGKILL,),
                     (helper.signal.SIGTERM, helper.signal.SIGKILL)):
        denied, resistant = helper.AuditToken(), helper.AuditToken()
        denied[5], denied[7] = 123, 456
        resistant[5], resistant[7] = 789, 987
        members = [denied, resistant]
        calls = []

        def send(pointer, sig):
            token = pointer._obj
            calls.append((token[5], sig))
            if token[5] == denied[5] and sig in rejected:
                return errno.EPERM
            if sig == helper.signal.SIGKILL and token in members:
                members.remove(token)
            return 0

        api = helper.Darwin.__new__(helper.Darwin)
        api.proc = Mock()
        api.proc.proc_signal_with_audittoken.side_effect = send
        api.fingerprint = Mock(return_value=(0, 0))
        api.members = Mock(side_effect=lambda directory: list(members))
        warning = io.StringIO()
        with patch.object(helper, 'Darwin', return_value=api), \
                patch.object(helper.sys, 'argv', ['helper', 'cleanup', '/unused']), \
                patch.object(helper.time, 'monotonic', side_effect=itertools.count()), \
                patch.object(helper.time, 'sleep'), contextlib.redirect_stderr(warning):
            result = helper.main()
        for pid in (123, 789):
            for sig in (helper.signal.SIGTERM, helper.signal.SIGKILL):
                assert (pid, sig) in calls, calls
        assert resistant not in members
        assert result == 1
        message = warning.getvalue()
        assert 'PID 123 generation 456' in message, message
        assert 'EPERM' in message, message
        for sig in rejected:
            assert helper.signal.Signals(sig).name in message, message
        assert 'detached descendants may survive' in message, message
        assert 'Traceback' not in message, message
    print('signal errors: TERM and KILL failures isolated; other member killed; PID and errno warned')


if __name__ == '__main__':
    {'pidfile': pidfile, 'probe': probe, 'signal-errors': signal_errors}[sys.argv[1]]()
