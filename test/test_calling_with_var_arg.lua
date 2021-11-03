local function add(v1, v2)
end

local function dummy()
end

local function format(fmt, ...)
end

local function resume(co, ok, err, ...)
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
resume(dummy())

-- ERROR
add(1, 2, 3, ...)
dummy(1, ...)
format()
resume()
resume(dummy(), 1)
