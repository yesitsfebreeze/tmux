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

The animation is the original smear-cursor.nvim engine, pinned at
`9e9378d6ee34bb3782e0e8c63d9ec8ca618b479b` with
`legacy_computing_symbols_support = true`, matching the installed Neovim
configuration. The unchanged upstream Lua modules provide diagonal/eighth
blocks, gradient/gamma, volume reduction, maximum trail length, elapsed-time
correction, debounce and mode-specific damping. LuaJIT runs them inside tmux;
there is no per-frame subprocess or runtime Lua-file loading.

The parity test compares the embedded engine against the pinned modules
running separately in Neovim. It checks emitted coordinates, glyphs, RGB
colours, visibility and next-frame timing across 673 deterministic frames,
including all directions, insertion, replace/command modes, retargeting,
window switching, scrolling, clipping and delayed frames. Actual wall-clock
presentation still depends on terminal rendering and scheduling.

For exact editor semantics, copy `examples/smear-tmux.lua` to Neovim's
`lua/config/smear-tmux.lua` and use `examples/smear-cursor.nvim.lua` as the lazy
plugin spec. The bridge requires Neovim 0.12's `nvim_ui_send`; it sends
pane-local numeric metadata via `OSC 777;smear-v1` (mode, Cursor/Normal
colours, window/buffer IDs and viewport scroll distance). This lets tmux
follow editor modes rather than guess them from cursor shape. Metadata is
ignored in copy mode and tmux prompts, and cleared on editor exit, terminal
reset or leaving the alternate screen. Applications without metadata use
block/vertical-bar/underline as normal/insert/replace respectively.

The plugin condition checks `tmux show-options -Av cursor-smear`; Neovim's
own renderer loads only when tmux does not own the cursor. Restart existing
Neovim processes after changing ownership. Transparent trail cells preserve
the current composed background, including coloured text and selections.

The vendored modules are GPL-3.0; their license and source hashes are in
`vendor/smear-cursor/`. Original tmux notices are retained.

Disable with `set -g cursor-smear off`; the old overlay is restored and the
ordinary terminal cursor resumes. The default is off.

## Build and verify

Use the regular tmux prerequisites plus LuaJIT and pkg-config. LuaJIT is
already a dependency of Homebrew Neovim on this machine. On macOS:

```sh
sh autogen.sh
./configure --prefix="$HOME/.local/opt/tmux-next" --enable-utf8proc --enable-jemalloc
make -j4
python3 regress/cursor-smear-parity.py
python3 regress/cursor-smear.py
make install
```

The regression launches two temporary tmux servers: one runs the renderer,
and the outer one acts as a real terminal emulator. It checks intermediate
frames, cursor visibility, Unicode text restoration, inactive panes, focus,
copy mode, command prompts, resizing and disabling the renderer. It kills only those test servers.
`TEST_TMUX_OUTER` optionally selects another tmux binary for the outer server.
`SMEAR_NVIM_CONFIG` optionally names the Neovim plugin spec to test the handoff
with both headless Neovim and a real Neovim TUI. `SMEAR_ORIGINAL` can name
a checkout of the original plugin to verify the vendored bytes against its
pinned Git revision as well as the recorded hashes.

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
