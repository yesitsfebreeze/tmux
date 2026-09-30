/*
 * C host for the unmodified GPL-3.0 smear-cursor.nvim modules.
 * See vendor/smear-cursor/LICENSE and UPSTREAM.json for license and provenance.
 * No user Lua, filesystem paths, or application strings are evaluated.
 */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "cursor-smear-engine.h"
#include "cursor-smear-lua.h"

struct smear_engine {
    lua_State *lua;
    struct smear_cell *cells;
    unsigned int count, capacity;
    int hidden;
    double delay;
    char error[256];
};

static int
smear_error(struct smear_engine *e)
{
    const char *message=lua_tostring(e->lua,-1);
    snprintf(e->error,sizeof e->error,"%s",message ? message : "smear engine error");
    lua_settop(e->lua,0);
    e->count=0;
    e->hidden=0;
    e->delay=-1;
    return (-1);
}

static int
smear_clock(lua_State *L)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    lua_pushnumber(L, now.tv_sec * 1000000000.0 + now.tv_nsec);
    return 1;
}

struct smear_engine *
smear_engine_new(void)
{
    struct smear_engine *e=calloc(1,sizeof *e);
    lua_State *L;
    unsigned int i;

    if (e==NULL) return NULL;
    L=e->lua=luaL_newstate();
    if (L==NULL) { free(e); return NULL; }
    luaL_openlibs(L);
    lua_pushcfunction(L,smear_clock); lua_setglobal(L,"smear_clock");
    lua_getglobal(L,"package");
    lua_getfield(L,-1,"preload");
    for (i=0;smear_lua_modules[i].name!=NULL;i++) {
        if (luaL_loadbuffer(L,smear_lua_modules[i].source,
            strlen(smear_lua_modules[i].source),smear_lua_modules[i].name)!=0) {
            smear_error(e);
            return e;
        }
        lua_setfield(L,-2,smear_lua_modules[i].name);
    }
    lua_settop(L,0);
    if (luaL_loadbuffer(L,smear_lua_host,sizeof smear_lua_host-1,"smear-host")!=0 ||
        lua_pcall(L,0,0,0)!=0) smear_error(e);
    return e;
}

void
smear_engine_free(struct smear_engine *e)
{
    if (e==NULL) return;
    lua_close(e->lua);
    free(e->cells);
    free(e);
}

static void
smear_number(lua_State *L,const char *key,double value)
{
    lua_pushnumber(L,value);
    lua_setfield(L,-2,key);
}

static double
smear_get_number(lua_State *L,const char *key)
{
    double value;
    lua_getfield(L,-1,key);
    value=lua_tonumber(L,-1);
    lua_pop(L,1);
    return value;
}

static int
smear_get_color(lua_State *L,const char *key)
{
    const char *value;
    int result=-1;
    lua_getfield(L,-1,key);
    value=lua_tostring(L,-1);
    if (value && value[0]=='#') result=(int)strtoul(value+1,NULL,16);
    lua_pop(L,1);
    return result;
}

int
smear_engine_step(struct smear_engine *e,const struct smear_input *in)
{
    lua_State *L=e->lua;
    unsigned int i,n;
    const char *text;
    size_t size;
    struct smear_cell *cell,*allocation;
    char mode[2]={in->mode,0};

    if (e->error[0]) return -1;
    lua_getglobal(L,"smear_step");
    lua_newtable(L);
#define FIELD(name) smear_number(L,#name,in->name)
    FIELD(row); FIELD(col); FIELD(width); FIELD(height); FIELD(now);
    FIELD(fg); FIELD(bg); FIELD(win); FIELD(buf); FIELD(top); FIELD(line); FIELD(scroll); FIELD(origin); FIELD(winheight);
#undef FIELD
    lua_pushboolean(L,in->reset); lua_setfield(L,-2,"reset");
    lua_pushboolean(L,in->realtime); lua_setfield(L,-2,"realtime");
    lua_pushstring(L,mode); lua_setfield(L,-2,"mode");
    if (lua_pcall(L,1,1,0)!=0) return smear_error(e);
    e->delay=smear_get_number(L,"delay");
    lua_getfield(L,-1,"hidden"); e->hidden=lua_toboolean(L,-1); lua_pop(L,1);
    lua_getfield(L,-1,"cells");
    n=(unsigned int)lua_objlen(L,-1);
    if (n>16384) {
        lua_pushliteral(L,"smear frame exceeds cell limit");
        return smear_error(e);
    }
    if (n>e->capacity) {
        allocation=realloc(e->cells,n*sizeof *e->cells);
        if (allocation==NULL) {
            lua_pushliteral(L,"cannot allocate smear frame");
            return smear_error(e);
        }
        e->cells=allocation; e->capacity=n;
    }
    e->count=n;
    for (i=0;i<n;i++) {
        lua_rawgeti(L,-1,i+1);
        cell=&e->cells[i];
        cell->row=smear_get_number(L,"row");
        cell->col=smear_get_number(L,"col");
        cell->blend=smear_get_number(L,"blend");
        cell->fg=smear_get_color(L,"fg");
        cell->bg=smear_get_color(L,"bg");
        lua_getfield(L,-1,"text");
        text=lua_tolstring(L,-1,&size);
        if (text==NULL || size>=sizeof cell->text) {
            lua_pushliteral(L,"invalid smear glyph");
            return smear_error(e);
        }
        memcpy(cell->text,text,size); cell->text[size]=0;
        lua_pop(L,2);
    }
    lua_settop(L,0);
    return 0;
}

int smear_engine_hidden(struct smear_engine *e) { return e->hidden; }
double smear_engine_delay(struct smear_engine *e) { return e->delay; }
unsigned int smear_engine_count(struct smear_engine *e) { return e->count; }
const struct smear_cell *smear_engine_cell(struct smear_engine *e,unsigned int i) { return &e->cells[i]; }
const char *smear_engine_error(struct smear_engine *e) { return e->error; }
