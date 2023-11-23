return function()
    local a = 1
    local b = 212
    local c = 'x'
    -- type(false and t) -> bool
    -- type(nil and t) -> nil
    -- type(other and t) -> t
    return (a and b) and c
end

-- return function(x)
--     if x+1 then
--         return 1
--     else
--         return 0
--     end
-- end

--return function(f)
--    return function(x)
--        return f(x + 1)
--    end
--end

-- return 1 + 2 + 3, 'a'..'b'
-- return 'a' .. 1
-- return 1 + 1

--if true then
--    return 1
--else
--    return 2
--end

--if true then
--    return 1
--else
--    return true
--end

--local function add(v1, v2)
--    return v1 + v2
--end
--
--local M = {}
--
--function M.strlen(s)
--    return #s
--end
--
--local function printfmt(fmt, ...)
--    print(string.format(fmt, ...))
--end
--
---- OK
--add(1, 2)
--M.strlen('foo')
--printfmt('ok')
--printfmt('%s', true)
--
---- ERROR
--add(1)
--add(1, 2, 3)
--M.strlen('foo', 1)
--printfmt()
