"""Harmless daemon fixture and end-to-end teardown checks. No agent harnesses."""
import os
import importlib.util
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True


def wait_for(predicate, description, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError(description)


def alive(pid):
    state = subprocess.run(['/bin/ps', '-o', 'stat=', '-p', str(pid)],
                           capture_output=True, text=True).stdout.strip()
    return bool(state) and not state.startswith('Z')


def read_pid(pidfile):
    try:
        text = Path(pidfile).read_text().strip()
    except FileNotFoundError:
        return None
    return int(text) if text else None


def daemon(pidfile, hold):
    pid = os.fork()
    if pid == 0:
        os.setsid()
        if os.fork():
            os._exit(0)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        with open(os.devnull, 'r+b', buffering=0) as null:
            for fd in (0, 1, 2):
                os.dup2(null.fileno(), fd)
        Path(pidfile).write_text(str(os.getpid()))
        time.sleep(60)
        os._exit(0)
    os.waitpid(pid, 0)
    wait_for(lambda: read_pid(pidfile), 'daemon did not start')
    print('daemon-ready', flush=True)
    if hold:
        time.sleep(60)


def check(scode, project, mode):
    project = Path(project)
    processes, descendants = [], []
    spec = importlib.util.spec_from_file_location(
        'strict_teardown', Path(__file__).resolve().parent.parent / 'lib/strict-teardown.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    api = helper.Darwin()
    cleanup_tokens = []
    outsider = subprocess.Popen(['/bin/sleep', '60'])
    processes.append(outsider)
    env = dict(os.environ, SCODE_CONFIG=str(project / 'empty.yaml'))
    (project / 'empty.yaml').touch()

    def launch(name, hold=False, logged=False):
        pidfile = project / (name + '.pid')
        args = [scode, '--strict', '--no-net', '-C', str(project),
                '--allow-ro', str(Path(__file__).resolve()),
                # The interpreter's own framework: CI's /usr/bin/python3 is
                # Xcode's, outside strict's system grants.
                '--allow-ro', os.path.realpath(sys.base_prefix)]
        if logged:
            args += ['--log', str(project / (name + '.log'))]
        args += ['--', sys.executable, '-I', str(Path(__file__).resolve()),
                 'daemon', str(pidfile), str(int(hold))]
        proc = subprocess.Popen(args, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        processes.append(proc)
        wait_for(lambda: read_pid(pidfile) or proc.poll() is not None, 'launch timed out')
        pid = read_pid(pidfile)
        if pid is None:
            raise AssertionError(proc.communicate())
        descendants.append(pid)
        cleanup_tokens.append(api.token(descendants[-1]))
        return proc, descendants[-1]

    try:
        if mode == 'concurrent':
            other, other_pid = launch('other', hold=True)
        proc, pid = launch('target', hold=mode in ('signal', 'quit'), logged=mode == 'log')
        if mode == 'signal':
            proc.terminate()
        elif mode == 'quit':
            proc.send_signal(signal.SIGQUIT)
        stdout, stderr = proc.communicate(timeout=20)
        assert 'teardown unavailable' not in stderr, stderr
        expected = {'signal': 143, 'quit': 131}.get(mode, 0)
        assert proc.returncode == expected, (proc.returncode, stderr)
        wait_for(lambda: not alive(pid), 'double-forked TERM-ignoring descendant survived', 3)
        assert outsider.poll() is None, 'unrelated process was signaled'
        if mode == 'concurrent':
            assert other.poll() is None and alive(other_pid), 'other sandbox was signaled'
            other.terminate()
            other.communicate(timeout=20)
            wait_for(lambda: not alive(other_pid), 'second sandbox descendant survived', 3)
        print(f'{mode}: detached descendant killed; outsider preserved; exit status preserved')
    finally:
        # Direct children remain owned by Popen. Detached fixtures require the
        # captured PID generation so failure cleanup cannot hit a reused PID.
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.communicate(timeout=20)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.communicate()
        for token in cleanup_tokens:
            if token is not None:
                api.send(token, signal.SIGKILL)


if __name__ == '__main__':
    if sys.argv[1] == 'daemon':
        daemon(sys.argv[2], bool(int(sys.argv[3])))
    else:
        check(*sys.argv[1:])
