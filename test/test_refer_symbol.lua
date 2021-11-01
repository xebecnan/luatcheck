
-->> $ :: number, number >> number
local function add(v1, v2)
    return v1 + v2
end

-->> $ :: open { }
local M = {}

-->> $ :: string >> integer
function M.strlen(s)
    return #s
end

-- luacheck: globals strcat
-->> $ :: string, string >> string
function strcat(s1, s2)
    return s1 .. s2
end

----------------

-- OK
add(1, 1)
M.strlen('a')
strcat('a', 'b')

-- ERROR
add(1)
add('a', 1)
add(1, 1, 1)
M.strlen()
M.strlen(1)
M.strlen('a', 'b')
strcat('a')
strcat(1, 2)
strcat('a', 'b', 1)
