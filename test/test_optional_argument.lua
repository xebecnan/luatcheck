
-->> try_add :: number, number? >> number
local function try_add(a, b)
    return a + (b or 0)
end

-->> add :: number, number >> number
local function add(a, b)
    return a + b
end

print(try_add(1, 2))
print(add(1, 2))

print(try_add())
print(try_add(1))
print(add(1))

print(try_add(1, 2, 3))
print(add(1, 2, 3))

-->> do_add :: (number, number >> number), number, number >> number
local function do_add(f_add, a, b)
    return f_add(a, b)
end

do_add(try_add, 3, 4)
do_add(add, 3, 4)
