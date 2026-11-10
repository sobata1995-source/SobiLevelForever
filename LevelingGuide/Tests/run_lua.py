#!/usr/bin/env python3
"""Run validation using the system Lua library; no WoW client is simulated here.

The Lua test file defines any mocks it needs. Lua 5.4 syntax/runtime validation
is separate from actual WoW Forever's protected-action and rendering behavior.
"""
import ctypes
import ctypes.util
import sys
from pathlib import Path

library = ctypes.util.find_library("lua5.4")
if not library:
    raise SystemExit("Lua 5.4 library unavailable")
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadfilex.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

syntax_only = "--syntax" in sys.argv[1:]
paths = [Path(p) for p in sys.argv[1:] if p != "--syntax"]
if not paths:
    raise SystemExit("usage: run_lua.py [--syntax] FILE.lua ...")
failed = False
for path in paths:
    runtime = lua.luaL_newstate()
    lua.luaL_openlibs(runtime)
    try:
        status = lua.luaL_loadfilex(runtime, str(path).encode(), None)
        if status == 0 and not syntax_only:
            status = lua.lua_pcallk(runtime, 0, -1, 0, 0, None)
        if status != 0:
            error = lua.lua_tolstring(runtime, -1, None)
            print(f"FAIL {path}: {error.decode(errors='replace') if error else status}", file=sys.stderr)
            failed = True
        elif syntax_only:
            print(f"PASS syntax: {path}")
    finally:
        lua.lua_close(runtime)
raise SystemExit(1 if failed else 0)
