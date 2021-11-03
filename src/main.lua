-- luacheck: globals lfs

local Parser = require('parser')
local Scoper = require('scoper')
local Binder = require('binder')
local Builtin = require('builtin')
local Typechecker = require('typechecker')
local SerializeAst = require 'serialize_ast'

local function usage()
    print('usage: typechecker.exe [--filename stdin_filename] file1, ...')
end

local function is_dir(path)
   return lfs.attributes(path, "mode") == "directory"
end

local function is_file(path)
   return lfs.attributes(path, "mode") == "file"
end

--------------------------------

local function check_file(c, filename)
    local ast = Parser(c, filename, true)
    if ast then
        -- print('-------------------------- Scoper')
        -- print(SerializeAst(ast))
        Scoper(ast)

        local root = Builtin(ast)

        -- print('-------------------------- Typechecker')
        local function msgh(s)

            print(SerializeAst(root))

            local s1, s2, s3 = s:match('^([^:]*):(%d+): (.*)$')
            if s1 and s2 and s3 then
                return debug.traceback(string.format('_:1: (%s:%s) %s', s1, s2, s3))
            else
                return debug.traceback(s)
            end
        end

        local ok, msg

        ok, msg = xpcall(Binder, msgh, root)
        if not ok then
            print(msg)
            return
        end

        ok, msg = xpcall(Typechecker, msgh, root)
        if not ok then
            print(msg)
            return
        end

        -- print(SerializeAst(root))
    end
end

local function iter_all_lua_files(dir, f)
    for e in lfs.dir(dir) do
        if e ~= '.' and e ~= '..' then
            local path = dir .. '/' .. e
            if is_file(path) then
                if string.match(path, '%.lua$') then
                    f(path)
                end
            elseif is_dir(path) then
                if e ~= '.git' then
                    iter_all_lua_files(path, f)
                end
            else
                error('bad path:' .. path)
            end
        end
    end
end

local function main(...)
    local n = select('#', ...)
    if n > 0 then
        local mode = nil
        local stdin_filename = nil
        for i = 1, n do
            local s = select(i, ...)
            if mode == 'STDIN_FILENAME' then
                stdin_filename = s
                mode = nil
            else
                if s == '--filename' then
                    mode = 'STDIN_FILENAME'
                elseif s == '-' then
                    local filename = stdin_filename or '=stdin'
                    local c = io.stdin:read('a')
                    io.stdin:close()
                    check_file(c, filename)
                elseif is_file(s) then
                    local f = io.open(s, 'r')
                    local c = f:read('a')
                    f:close()
                    check_file(c, s)
                elseif is_dir(s) then
                    iter_all_lua_files(s, function(filepath)
                        local f = io.open(filepath, 'r')
                        local c = f:read('a')
                        f:close()
                        check_file(c, filepath)
                    end)
                else
                    error('bad argument: ' .. s)
                end
            end
        end
    else
        usage()
    end
end

local msgh = function(s)
    local s1, s2, s3 = s:match('^([^:]*):(%d+): (.*)$')
    if s1 and s2 and s3 then
        return debug.traceback(string.format('_:1: (%s:%s) %s', s1, s2, s3))
    else
        return debug.traceback(s)
    end
end

local ok, msg = xpcall(main, msgh, ...)
if not ok then
    print(msg)
end
