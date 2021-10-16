
-->> recusive_func :: integer >> integer
local function recusive_func(v)
    return recusive_func(v)
end

print(recusive_func(3))
