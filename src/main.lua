local Parser = require('parser')
local Binder = require('binder')
local Typechecker = require('typechecker')

local function usage()
    print('usage: typechecker.exe file1, ...')
end

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
        Binder(ast)
        Typechecker(ast)
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
    return debug.traceback(string.format('_:1: (%s:%d) %s', s1, s2, s3))
end

local ok, msg = xpcall(main, msgh, ...)
if not ok then
    print(msg)
end
