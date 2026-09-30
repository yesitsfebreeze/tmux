#!/usr/bin/env python3
"""Exercise the real client renderer inside a second tmux terminal emulator."""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time

binary = str(Path(__file__).resolve().parents[1] / 'tmux')
suffix = str(os.getpid())
env = dict(os.environ, TERM='xterm-256color', LC_ALL='en_US.UTF-8')
env.pop('TMUX', None)
inner = [binary, '-L', 'smear-inner-' + suffix, '-f', '/dev/null']
outer = [os.environ.get('TEST_TMUX_OUTER', binary), '-L', 'smear-outer-' + suffix, '-f', '/dev/null']

def run(server, *args, check=True):
    return subprocess.run(server + list(args), env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=check).stdout.rstrip('\n')

def capture():
    return run(outer, 'capture-pane', '-p')

def key(pane, value):
    run(inner, 'send-keys', '-t', pane, '-l', value)

def collect(duration=.5):
    end = time.monotonic() + duration
    frames = []
    flags = []
    while time.monotonic() < end:
        frames.append(capture())
        flags.append(run(outer, 'display-message', '-p', '#{cursor_flag}'))
        time.sleep(.01)
    return frames, flags

try:
    with tempfile.TemporaryDirectory(prefix='tmux-smear-') as temp:
        fixture = Path(temp) / 'fixture.py'
        fixture.write_text('''import os, tty
from shutil import get_terminal_size
tty.setraw(0)
w,h=get_terminal_size()
os.write(1,b'\\x1b[2J')
for y in range(h):
    text=("a界ébcdefghijklmnopqrstuvwxyz"*10)[:max(1,w//2)]
    os.write(1,(f"\\x1b[{y+1};1H"+text).encode())
os.write(1,b'\\x1b[2;3H\\x1b[?25h')
while True:
    key=os.read(0,1)
    if not key: break
    outputs={b'm':f'\\x1b[{max(2,h-3)};{max(3,w-4)}H',b'n':'\\x1b[2;3H',
             b'h':'\\x1b[?25l',b's':'\\x1b[?25h',b'b':'\\x1b[5 q',
             b'u':'\\x1b[3 q',b'c':'\\x1b[1 q'}
    os.write(1,outputs.get(key,'').encode())
''')
        command = shlex.join([sys.executable, '-u', str(fixture)])
        run(inner, 'new-session', '-d', '-x', '70', '-y', '20', command)
        run(inner, 'set-option', '-g', 'status', 'off')
        run(inner, 'set-option', '-g', 'focus-events', 'on')
        run(inner, 'set-option', '-g', 'cursor-smear', 'on')
        p1 = run(inner, 'display-message', '-p', '#{pane_id}')
        run(outer, 'new-session', '-d', '-x', '70', '-y', '20',
            shlex.join(inner + ['attach-session']))
        run(outer, 'set-option', '-g', 'status', 'off')
        time.sleep(.7)
        baseline = capture()
        content = run(inner, 'capture-pane', '-p', '-t', p1)
        key(p1, 'm')
        frames, flags = collect()
        assert any(frame != baseline for frame in frames), 'no visible animation'
        assert '0' in flags, 'physical cursor was not hidden during animation'
        assert capture() == baseline, 'trail damaged final terminal contents'
        assert flags[-1] == '1', 'physical cursor did not return'
        assert run(inner, 'capture-pane', '-p', '-t', p1) == content, 'application grid changed'
        print('PASS: visible trail, one cursor, Unicode text restored, application grid untouched')
        for shape in ('b', 'u', 'c'):
            key(p1, shape)
            key(p1, 'n')
            collect()
            assert capture() == baseline, 'shape change left stale cells'
            key(p1, 'm')
            collect()
            assert capture() == baseline
        print('PASS: bar, underline and block settle without residue')
        key(p1, 'n')
        time.sleep(.025)
        key(p1, 'h')
        collect()
        assert capture() == baseline, 'hidden cursor left a trail'
        assert run(outer, 'display-message', '-p', '#{cursor_flag}') == '0'
        key(p1, 's')
        time.sleep(.2)
        print('PASS: cursor visibility cancels and clears animation')
        p2 = run(inner, 'split-window', '-h', '-P', '-F', '#{pane_id}', command)
        time.sleep(.6)
        split_baseline = capture()
        key(p1, 'm')
        frames, flags = collect()
        assert all(frame == split_baseline for frame in frames), 'inactive pane animated'
        run(inner, 'select-pane', '-t', p1)
        frames, flags = collect()
        assert any(frame != frames[-1] for frame in frames), 'pane switch did not animate'
        settled = capture()
        key(p2, 'm')
        frames, flags = collect()
        assert all(frame == settled for frame in frames), 'second inactive pane animated'
        print('PASS: pane switches animate; background cursor moves do not')
        key(p1, 'n')
        time.sleep(.025)
        run(inner, 'set-option', '-g', 'cursor-smear', 'off')
        collect()
        assert capture() == settled, 'disabling smear left residue'
        print('PASS: disabling renderer restores screen')
        run(inner, 'set-option', '-g', 'cursor-smear', 'on')
        run(outer, 'send-keys', '-l', '\x1b[O')
        collect()
        assert run(outer, 'display-message', '-p', '#{cursor_flag}') == '0', 'unfocused cursor visible'
        key(p1, 'm')
        frames, flags = collect()
        assert all(frame == settled for frame in frames), 'unfocused client animated'
        run(outer, 'send-keys', '-l', '\x1b[I')
        collect()
        assert run(outer, 'display-message', '-p', '#{cursor_flag}') == '1'
        print('PASS: focus loss hides cursor and cancels animation; focus return restores it')
        run(inner, 'copy-mode', '-t', p1)
        time.sleep(.5)
        run(inner, 'send-keys', '-t', p1, '-X', 'start-of-line')
        frames, flags = collect()
        assert '0' in flags, 'copy-mode movement did not animate'
        run(inner, 'send-keys', '-t', p1, '-X', 'cancel')
        collect()
        assert capture() == settled, 'copy-mode left residue'
        print('PASS: copy-mode uses the same animation and restores content')
        prompt = subprocess.Popen(inner + ['command-prompt', '-p', 'smear-test:', 'display-message %%'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        frames, flags = collect()
        assert '0' in flags and flags[-1] == '1', ('command prompt cursor did not animate', flags, capture())
        run(outer, 'send-keys', 'C-c')
        prompt.communicate(timeout=5)
        assert prompt.returncode == 0
        collect()
        assert capture() == settled, 'command prompt left residue'
        print('PASS: command prompt shares the renderer and restores the screen')
        key(p1, 'n')
        time.sleep(.025)
        run(outer, 'resize-window', '-x', '65', '-y', '18')
        collect()
        assert run(outer, 'display-message', '-p', '#{cursor_flag}') == '1'
        before_refresh = capture()
        run(inner, 'refresh-client')
        collect()
        assert capture() == before_refresh, 'resize left stale overlay cells'
        print('PASS: resize cancels old coordinates without stale cells')
        if env.get('SMEAR_NVIM_CONFIG'):
            lua = Path(temp) / 'check.lua'
            lua.write_text('local p=dofile(vim.env.SMEAR_NVIM_CONFIG); print(p[1].cond() and "fallback" or "tmux"); vim.cmd("qa!")')
            nvim_env = dict(env, PATH=str(Path(binary).parent) + os.pathsep + env.get('PATH', ''), TMUX=run(inner, 'display-message', '-p', '#{socket_path},#{pid},0'))
            def nvim_owner(environment):
                result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-l', str(lua)], env=environment, text=True, capture_output=True, check=True)
                return (result.stdout + result.stderr).strip()
            assert nvim_owner(nvim_env) == 'tmux', (nvim_owner(nvim_env), run(inner, 'show-options', '-v', 'cursor-smear'), nvim_env['TMUX'])
            run(inner, 'set-option', '-g', 'cursor-smear', 'off')
            assert nvim_owner(nvim_env) == 'fallback'
            assert nvim_owner(env) == 'fallback'
            print('PASS: real Neovim disables its duplicate only when tmux owns the cursor')

finally:
    run(outer, 'kill-server', check=False)
    run(inner, 'kill-server', check=False)
