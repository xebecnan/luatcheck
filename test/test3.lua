-- luacheck: ignore 212

---- local t = { foo = function() return 'ok' end }
---->> t :: { field : string >> number; }
--local t = { field=function(s) return #s end }
--
--print(t.field[1].bar:foo())

-->> N = { a:number; b:string; }

-->> M :: open { }
local M = {}

-->> M.strlen :: string >> integer
function M:strlen(s)
    return #s
end

-- function M.foobar()
-- end

print(M.strlen())
print(M.strlen(''))
print(M.strlen('aa', 'bb'))
M.strlen(M.strlen('test'))

-->> close M
return M
