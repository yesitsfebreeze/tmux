# Pinned upstream engine

These six Lua modules are unmodified copies from sphamba/smear-cursor.nvim,
revision 9e9378d6ee34bb3782e0e8c63d9ec8ca618b479b. UPSTREAM.json records their
SHA-256 digests. Their original GPL version 3 license is preserved in LICENSE.

The compiled personal tmux build includes these GPL-3.0 modules. Original
tmux copyright and ISC notices remain in their source files and COPYING;
distribution of this combined build must also comply with the included GPL.

The separate cursor-smear-host.lua adapts Neovim events, clocks, highlights
and floating-cell output to a tmux client. It does not replace the animation,
rasterization or colour algorithms. tools/embed-cursor-smear.py embeds the
pinned files and adapter; no Lua source is loaded from disk at runtime.
