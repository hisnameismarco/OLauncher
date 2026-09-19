"""Cancellable filename search. Arguments and results are data, never shell code."""
import json
import os
import signal
import subprocess
import sys

child = None

def cancel(*_):
    if child is not None:
        child.terminate()
        child.wait()
    sys.exit(0)

signal.signal(signal.SIGTERM, cancel)
token, query, home = sys.argv[1:]
try:
    child = subprocess.Popen(
        ['fd', '--fixed-strings', '--ignore-case', '--absolute-path', '--type', 'f',
         '--max-depth', '8', '--max-results', '80', '--print0', '--color', 'never',
         '--exclude', 'node_modules', '--exclude', '.git', '--', query, home],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    data, error = child.communicate(timeout=8)
    paths = [os.fsdecode(p) for p in data.split(b'\0') if p]
    paths.sort(key=lambda p: (os.path.basename(p).casefold() != query.casefold(),
                             not os.path.basename(p).casefold().startswith(query.casefold()), len(p), p))
    print(json.dumps({'token': int(token), 'paths': paths[:40],
                      'error': error.decode(errors='replace').strip() if child.returncode else ''}))
except (OSError, subprocess.TimeoutExpired) as exc:
    if child is not None and child.poll() is None:
        child.kill()
        child.wait()
    print(json.dumps({'token': int(token), 'paths': [], 'error': str(exc)}))
