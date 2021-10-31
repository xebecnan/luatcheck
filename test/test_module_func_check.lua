-->> M :: open { }
local M = {}

-->> M.strlen :: string >> integer
function M.strlen(s)
    return #s
end

-->> M.func_to_be_checked :: void >> void
function M.func_to_be_checked()
    -- ok
    M.strlen('a')
    M.func_defined_after(1)

    -- error
    M.strlen(1)
    M.func_defined_after('a')
end

-->> M.func_defined_after :: number >> string
function M.func_defined_after(n)
    return tostring(n)
end

-->> close M
return M
