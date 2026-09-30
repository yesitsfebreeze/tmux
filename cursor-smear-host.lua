-- Host adapter only. The pinned upstream modules remain byte-for-byte intact.
-- Coordinates are one-based, like Neovim's editor grid.
local state = { row=1, col=1, mode='n', now=1, width=80, height=24,
    fg=0xd0d0d0, bg=-1, win=1, buf=1, top=1, line=1, scroll=0, origin=0, winheight=24 }
local cells, highlights, timers = {}, {}, {}
local hidden, animation, events, initialized = false, nil, nil, false
local function clock() return state.realtime and smear_clock() / 1000000 or state.now end
local function schedule(fn, delay)
    local timer = { fn=fn, due=clock() + math.max(0, delay), active=true }
    timers[#timers+1] = timer
    return timer
end
local function utf8(code)
    if code < 128 then return string.char(code) end
    if code < 2048 then return string.char(192+math.floor(code/64),128+code%64) end
    if code < 65536 then
        return string.char(224+math.floor(code/4096),128+math.floor(code/64)%64,128+code%64)
    end
    return string.char(240+math.floor(code/262144),128+math.floor(code/4096)%64,
        128+math.floor(code/64)%64,128+code%64)
end
vim = {
    o={lines=24,columns=80,guicursor='',ei=''}, opt={cmdheight={_value=0}},
    bo={filetype=''}, log={levels={INFO=2}}, cmd={redraw=function() end},
    notify=function(message) error(message) end,
    tbl_contains=function(t, value) for _,v in ipairs(t) do if v==value then return true end end return false end,
    schedule_wrap=function(fn) return fn end,
    defer_fn=function(fn, delay) return schedule(fn, delay) end,
    uv={hrtime=function() return state.realtime and smear_clock() or state.now * 1000000 end},
    fn={nr2char=utf8, has=function() return 1 end,
        line=function(which) return which=='w0' and state.top or state.line end},
    api={
        nvim_create_namespace=function() return 1 end,
        nvim_get_mode=function() return {mode=state.mode} end,
        nvim_get_current_win=function() return state.win end,
        nvim_get_current_buf=function() return state.buf end,
        nvim_win_get_position=function() return {state.origin,0} end,
        nvim_win_get_height=function() return state.winheight end,
        nvim_get_hl=function(_, opts)
            if opts.name=='Cursor' then return {bg=state.fg} end
            if opts.name=='Normal' then return {fg=state.fg,bg=state.bg >= 0 and state.bg or nil} end
            return {}
        end,
        nvim_set_hl=function(_, name, value)
            highlights[name] = value
            if name=='SmearCursorHideable' then hidden=value.blend==100 end
        end,
    },
}
vim.uv.new_timer = function()
    local handle = {}
    function handle:start(delay, _, fn) self.timer=schedule(fn, delay) end
    function handle:is_active() return self.timer and self.timer.active end
    function handle:stop() if self.timer then self.timer.active=false end end
    handle.close=handle.stop
    return handle
end
package.preload['smear_cursor.screen'] = function()
    return {
        get_screen_cursor_position=function() return state.row,state.col end,
        get_screen_cmd_cursor_position=function() return state.row,state.col end,
        get_screen_distance=function() return state.scroll end,
    }
end
local config = require('smear_cursor.config')
config.legacy_computing_symbols_support = true
local color = require('smear_cursor.color')
local draw = require('smear_cursor.draw')
-- Only the rendering destination changes: tmux cells instead of float windows.
draw.draw_character = function(row,col,character,group)
    if row<1 or row>state.height or col<1 or col>state.width then return end
    local hl = assert(highlights[group], 'missing smear highlight')
    cells[#cells+1]={row=row,col=col,text=character,fg=hl.fg,bg=hl.bg,blend=hl.blend or 0}
end
draw.clear = function() cells={} end
local function reset()
    timers, cells = {}, {}
    hidden = false
    package.loaded['smear_cursor.animation']=nil
    package.loaded['smear_cursor.events']=nil
    animation=require('smear_cursor.animation')
    events=require('smear_cursor.events')
end
local function drain()
    -- Run ready timers at the supplied monotonic instant, as an event loop does.
    for _=1,100 do
        local ready=nil
        for _,timer in ipairs(timers) do
            if timer.active and timer.due<=clock() and (not ready or timer.due<ready.due) then ready=timer end
        end
        if not ready then break end
        ready.active=false
        ready.fn()
    end
    local active, next_due={},nil
    for _,timer in ipairs(timers) do
        if timer.active then
            active[#active+1]=timer
            next_due=math.min(next_due or timer.due,timer.due)
        end
    end
    timers=active
    return next_due and math.max(0,next_due-clock()) or -1
end
function smear_step(input)
    local changed=state.row~=input.row or state.col~=input.col or state.mode~=input.mode
        or state.win~=input.win or state.buf~=input.buf or state.top~=input.top
    local recolor=state.fg~=input.fg or state.bg~=input.bg
    state=input
    vim.o.lines, vim.o.columns=state.height,state.width
    if recolor then color.clear_cache() end
    if not initialized or input.reset then
        reset()
        drain() -- upstream's deferred initialization reads the new coordinates
        animation.jump(state.row,state.col)
        initialized=true
    elseif changed then
        events.move_cursor()
    end
    local delay=drain()
    return { cells=cells, hidden=hidden, delay=delay }
end
