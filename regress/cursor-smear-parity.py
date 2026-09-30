#!/usr/bin/env python3
"""Compare the embedded engine with the original modules running in Neovim."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
vendor=root/'vendor/smear-cursor'
manifest=json.loads((vendor/'UPSTREAM.json').read_text())
for name,digest in manifest['sha256'].items():
    assert hashlib.sha256((vendor/name).read_bytes()).hexdigest()==digest, name+' differs from pinned upstream'
original=os.environ.get('SMEAR_ORIGINAL')
if original:
    for name in manifest['sha256']:
        data=subprocess.check_output(['git','-C',original,'show',manifest['revision']+':lua/smear_cursor/'+name])
        assert data==(vendor/name).read_bytes(), name+' differs from original Git revision'

with tempfile.TemporaryDirectory(prefix='smear-parity-') as tmp:
    tmp=Path(tmp)
    executable=tmp/'engine'
    flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','luajit'],text=True))
    subprocess.run(['cc','-std=c99','-Wall','-Wextra','-I',str(root),
        str(root/'regress/cursor-smear-engine.c'),str(root/'cursor-smear-engine.c'),
        '-o',str(executable)]+flags,check=True)
    trace=[]
    now=1000
    # Directions, short moves, mode changes, retargeting, lag, window switch,
    # scroll compensation, transparent/opaque backgrounds, clipped edges.
    cases=[
        ('n',12,40,12,65),('n',12,40,12,10),('n',12,40,3,40),('n',12,40,22,40),
        ('n',12,40,2,2),('n',12,40,2,78),('n',12,40,23,2),('n',12,40,23,78),
        ('n',12,40,13,41),('i',12,40,12,41),('i',12,40,20,72),
        ('c',12,40,24,10),('R',12,40,20,70),('n',1,1,24,80),
    ]
    def add(t,row,col,mode,reset=0,bg=-1,win=1,top=1,line=1,scroll=0,fg=0xd4be98):
        trace.append(f'{t} {row} {col} {mode} {reset} 80 24 {fg} {bg} {win} 1 {top} {line} {scroll} 0 24\n')
    for index,(mode,row,col,target_row,target_col) in enumerate(cases):
        bg=-1 if index%2 else 0x282828
        add(now,row,col,mode,reset=1,bg=bg)
        for offset in [1,2,3]+list(range(20,701,17)):
            add(now+offset,target_row,target_col,mode,bg=bg)
        now+=1000
    add(now,12,40,'n',reset=1)
    for offset in [1,2,3,20,37,54,100,117,134,151,400,417,434,451,700]:
        row,col=(3,70) if offset<50 else (20,8)
        add(now+offset,row,col,'i' if offset>=100 else 'n',win=2 if offset>=400 else 1)
    now+=1000
    add(now,12,40,'n',reset=1)
    for offset in [1,2,3]+list(range(20,401,17)):
        add(now+offset,8,40,'n',top=5,line=10,scroll=4,fg=0xa9b665)
    tracefile=tmp/'trace';tracefile.write_text(''.join(trace))
    actual=subprocess.check_output([str(executable)],input=tracefile.read_bytes()).decode()
    env=dict(os.environ,SMEAR_UPSTREAM=str(vendor),SMEAR_TRACE=str(tracefile))
    oracle=subprocess.run(['nvim','--headless','-u','NONE','-l',str(root/'regress/cursor-smear-oracle.lua')],
        env=env,text=True,capture_output=True,check=True)
    expected=oracle.stdout
    if actual!=expected:
        diff=''.join(difflib.unified_diff(expected.splitlines(True),actual.splitlines(True),fromfile='Neovim',tofile='tmux'))
        print(diff[:16000])
        raise AssertionError('smear frame parity failed')
    cells=[line for line in actual.splitlines() if line.startswith('C ')]
    assert len(cells)>100
    assert any(any(0x1fb00<=ord(ch)<=0x1fbff for ch in line) for line in cells), 'no legacy diagonal glyphs exercised'
    assert len({line.split()[-3] for line in cells})>16, 'no colour gradient exercised'
    print(f'PASS: {len(trace)} frames and {len(cells)} glyph/colour records exactly match original Neovim modules')
    print('PASS: pinned source hashes, eight directions, insert/replace/command modes, retargeting, lag, pane switch, scroll, clipping, shading')
