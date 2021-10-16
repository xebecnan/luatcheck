local Parser = require('parser')
local Binder = require('binder')
local Typechecker = require('typechecker')
local SerializeAst = require 'serialize_ast'

local function usage()
    print('usage: typechecker.exe file1, ...')
end

--------------------------------

local BUILTIN = [[
-->> print :: ... >> void
]]

local function init_global_symbols()
    local ast = Parser(BUILTIN, 'BUILTIN')
    Binder(ast)
    Typechecker(ast)
    return ast.symbols
end

--------------------------------

local function check_file(filepath)
    local f = io.open(filepath, 'r')
    if not f then
        io.stderr:write("file not found: " .. filepath .. "\n")
        return
    end

    local c = f:read('a')
    f:close()

    local ast = Parser(c, filepath, true)
    if ast then
        -- print('-------------------------- Binder')
        -- print(SerializeAst(ast))
        Binder(ast)

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
        local ok, msg = xpcall(Typechecker, msgh, root)
        if not ok then
            print(msg)
        -- else
        --     print(SerializeAst(root))
        end
    end
end

local function main(...)
    local n = select('#', ...)
    if n > 0 then
        for i = 1, n do
            local s = select(i, ...)
            check_file(s)
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
