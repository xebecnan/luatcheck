local function add(v1, v2)
end

local function dummy()
end

local function format(fmt, ...)
end

-- OK
add(...)
add(1, ...)
add(1, 2, ...)
dummy(...)
format('s')
format('s', 1)
format(...)
format('s', ...)
format('s', 1, ...)

-- ERROR
add(1, 2, 3, ...)
dummy(1, ...)
format()
