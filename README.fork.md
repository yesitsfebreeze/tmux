# Personal tmux build

This fork keeps the `personal` branch as the daily-driver build. It starts
from upstream plus PR #5433 (the existing separate/rounded pane frames),
and adds an opt-in client-owned cursor smear. `upstream` remains tmux/tmux.

## Cursor smear

```tmux
set -g focus-events on
set -g cursor-smear on
```

There is one animated cursor per focused terminal client. Its target is the
final screen coordinate after tmux selects the active pane, copy-mode cursor,
menu or command prompt. Pane and window switches use the same animation.
Applications that hide the cursor keep it hidden. Focus loss cancels the
trail and hides the physical cursor. Non-UTF-8 clients use the normal cursor.

The physical cursor is hidden while the cell overlay moves, then restored
with the application's shape and colour when the animation settles. Overlay
cells never enter pane grids or scrollback. Damaged rows are restored from
the current composed scene, including borders, floating panes and status;
an application redraw cannot make a saved text snapshot overwrite new text.

Motion uses the normal-mode spring parameters from smear-cursor.nvim:
17 ms frames, head stiffness .6, tail stiffness .45, anticipation .2,
damping .85. Rasterization currently uses Unicode quadrant blocks. This is
not a pixel-identical port of that plugin's legacy diagonal glyphs, shading,
or mode-specific motion. Using this one renderer for every application gives
them consistent motion, but visual comparison with the original remains open.

Do not run an application-side cursor animation at the same time. Neovim's
plugin can check the inherited option with `tmux show-options -Av cursor-smear`;
keep the plugin only if the command fails or does not return `on`. Restart
existing Neovim processes after changing which renderer owns the cursor.

Disable with `set -g cursor-smear off`; the old overlay is restored and the
ordinary terminal cursor resumes. The default is off.

## Build and verify

Use the regular tmux build prerequisites and configure flags for your host:

```sh
sh autogen.sh
./configure --prefix="$HOME/.local/opt/tmux-next"
make -j4
python3 regress/cursor-smear.py
make install
```

The regression launches two temporary tmux servers: one runs the renderer,
and the outer one acts as a real terminal emulator. It checks intermediate
frames, cursor visibility, Unicode text restoration, inactive panes, focus,
copy mode, command prompts, resizing and disabling the renderer. It kills only those test servers.
`TEST_TMUX_OUTER` optionally selects another tmux binary for the outer server.
`SMEAR_NVIM_CONFIG` optionally names the Neovim plugin spec to test the handoff
with a real headless Neovim process.

Installing a binary does not replace an already-running tmux server. Existing
sessions continue on the old executable until the server is restarted. Never
kill an occupied server merely to activate a cosmetic feature. For a preview,
start a separate server with `tmux -L smear-preview -f /dev/null new-session`,
then enable the two options above on that server.

## Baseline test limitation

On the macOS daily-driver setup, `regress/screen-redraw-menus.sh` differs
from its golden file at `menu-over-split`. The same case fails with the
previously installed frame-patched binary (before cursor-smear). The cursor
regression passes; this pre-existing golden mismatch is not claimed fixed.
