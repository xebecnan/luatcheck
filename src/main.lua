local Parser = require('parser')
local Scoper = require('scoper')
local Binder = require('binder')
local Typechecker = require('typechecker')
local SerializeAst = require 'serialize_ast'

local function usage()
    print('usage: typechecker.exe [--filename stdin_filename] file1, ...')
end

--------------------------------

local BUILTIN = [[
-->> print :: ... >> void
-->> require :: string >> module
]]

local function init_global_symbols()
    local ast = Parser(BUILTIN, 'BUILTIN')
    Scoper(ast)
    Binder(ast)
    return ast.symbols
end

--------------------------------

local function check_file(filepath, stdin_filename)
    local f
    local filename
    if filepath == '-' then
        f = io.stdin
        filename = stdin_filename or '=stdin'
    else
        filename = filepath
        f = io.open(filename, 'r')
        if not f then
            io.stderr:write("file not found: " .. filename .. "\n")
            return
        end
    end

    local c = f:read('a')
    f:close()

    local ast = Parser(c, filename, true)
    if ast then
        -- print('-------------------------- Scoper')
        -- print(SerializeAst(ast))
        Scoper(ast)

        local root = { tag='Block', info=ast.info, symbols=init_global_symbols(), types={}, ast }
        ast.parent = root
        root.scope = root

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
                else
                    check_file(s, stdin_filename)
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
