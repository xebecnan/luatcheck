-->> assert_func :: boolean >> void
local function assert_func(v)
    if not v then
        error('assert failed')
    end
end


local function foo()
    -->> bar :: number >> number
    local function bar(v)
        return v + 1
    end

    bar(1)
    bar(1.1)
    bar('a')
    bar({})
    bar(false)
    bar(true)

    assert_func(10 > 1)
    assert_func(10)
end

local function bar()
    -->> bar :: string >> number
    local function bar(v)
        return #v
    end

    bar(1)
    bar(1.1)
    bar('a')
    bar({})
    bar(false)
    bar(true)

    assert_func(true)
    assert_func(print())
end

-->> add :: number, number >> number
local function add(a, b)
    return a + b
end

add(1, 2)

-->> do_add :: (number, number >> number), number, number >> number
local function do_add(f_add, a, b)
    return f_add(a, b)
end

do_add(assert_func, 3, 4)
do_add(add, 3, 4)

--[[>>
AstNode = {
    tag : string;
    info : any;
    scope : any;
}
ast_error :: AstNode, string, ... >> void
<<]]
local function ast_error(ast, fmt, ...)
    local info = ast and ast.info or {}
    print(string.format('%s:%d: ' .. fmt, info.filename or '?', info.line or 0, ...))
end

local ast = {}

ast_error(ast, 'test error')
