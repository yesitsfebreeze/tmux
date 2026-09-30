-- Independent oracle: original modules, real Neovim highlight resolution,
-- deterministic inputs and clock. No production host adapter is loaded.
package.path = vim.env.SMEAR_UPSTREAM .. '/?.lua;' .. package.path
local names={'config','math','draw','color','animation','events'}
for _,name in ipairs(names) do
    package.preload['smear_cursor.'..name]=assert(loadfile(vim.env.SMEAR_UPSTREAM..'/'..name..'.lua'))
end
local input, queue, hidden, cells = {}, {}, false, {}
local function later(callback,delay)
    local t={callback=callback,at=input.now+math.max(delay,0),active=true}
    queue[#queue+1]=t
    return t
end
vim.defer_fn=later
vim.schedule_wrap=function(f) return f end
vim.uv.hrtime=function() return input.now*1000000 end
vim.uv.new_timer=function()
    local h={}
    function h:start(delay,_,f) self.task=later(f,delay) end
    function h:is_active() return self.task and self.task.active end
    function h:stop() if self.task then self.task.active=false end end
    h.close=h.stop
    return h
end
vim.api.nvim_get_mode=function() return {mode=input.mode} end
vim.api.nvim_get_current_win=function() return input.win end
vim.api.nvim_get_current_buf=function() return input.buf end
vim.api.nvim_win_get_position=function() return {input.origin,0} end
vim.api.nvim_win_get_height=function() return input.winheight end
vim.fn.line=function(v) return v=='w0' and input.top or input.line end
vim.cmd.redraw=function() end
local set_hl=vim.api.nvim_set_hl
vim.api.nvim_set_hl=function(ns,name,hl)
    if name=='SmearCursorHideable' then hidden=hl.blend==100 end
    set_hl(ns,name,hl)
end
package.preload['smear_cursor.screen']=function()
    return {get_screen_cursor_position=function() return input.row,input.col end,
        get_screen_cmd_cursor_position=function() return input.row,input.col end,
        get_screen_distance=function() return input.scroll end}
end
local config=require('smear_cursor.config')
config.legacy_computing_symbols_support=true
local color=require('smear_cursor.color')
local draw=require('smear_cursor.draw')
draw.clear=function() cells={} end
draw.draw_character=function(row,col,glyph,group)
    if row<1 or row>input.height or col<1 or col>input.width then return end
    local hl=vim.api.nvim_get_hl(0,{name=group,link=false})
    cells[#cells+1]={row,col,glyph,hl.fg or -1,hl.bg or -1,hl.blend or 0}
end
local function pump()
    for _=1,100 do
        local first
        for _,t in ipairs(queue) do
            if t.active and t.at<=input.now and (not first or t.at<first.at) then first=t end
        end
        if not first then break end
        first.active=false
        first.callback()
    end
    local next_at,keep=nil,{}
    for _,t in ipairs(queue) do
        if t.active then keep[#keep+1]=t; next_at=math.min(next_at or t.at,t.at) end
    end
    queue=keep
    return next_at and math.max(0,next_at-input.now) or -1
end
local animation,events,previous
for line in io.lines(vim.env.SMEAR_TRACE) do
    local a={}
    for v in line:gmatch('%S+') do a[#a+1]=tonumber(v) or v end
    input={now=a[1],row=a[2],col=a[3],mode=a[4],reset=a[5]==1,width=a[6],height=a[7],
        fg=a[8],bg=a[9],win=a[10],buf=a[11],top=a[12],line=a[13],scroll=a[14],origin=a[15],winheight=a[16]}
    vim.o.lines=input.height; vim.o.columns=input.width; vim.o.cmdheight=0
    set_hl(0,'Cursor',{bg=input.fg})
    set_hl(0,'Normal',{fg=input.fg,bg=input.bg>=0 and input.bg or 'NONE'})
    if not previous or previous.fg~=input.fg or previous.bg~=input.bg then color.clear_cache() end
    if not previous or input.reset then
        queue={}; cells={}; hidden=false
        package.loaded['smear_cursor.animation']=nil
        package.loaded['smear_cursor.events']=nil
        animation=require('smear_cursor.animation')
        events=require('smear_cursor.events')
        pump()
        animation.jump(input.row,input.col)
    elseif previous.row~=input.row or previous.col~=input.col or previous.mode~=input.mode
        or previous.win~=input.win or previous.buf~=input.buf or previous.top~=input.top then
        events.move_cursor()
    end
    local delay=pump()
    io.write(string.format('F %d %.6f %d\n',hidden and 1 or 0,delay,#cells))
    for _,c in ipairs(cells) do io.write(string.format('C %d %d %s %d %d %d\n',unpack(c))) end
    previous=input
end
vim.cmd('qa!')
