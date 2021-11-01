local function add(v1, v2)
    return v1 + v2
end

local M = {}

function M.strlen(s)
    return #s
end

local function printfmt(fmt, ...)
    print(string.format(fmt, ...))
end

-- OK
add(1, 2)
M.strlen('foo')
printfmt('ok')
printfmt('%s', true)

-- ERROR
add(1)
add(1, 2, 3)
M.strlen('foo', 1)
printfmt()
