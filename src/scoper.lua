-- Scoper 主要是处理 scope 设置

local Walk = require('walk')

--------------------------------

local function init_scope(ast, parent)
    ast.parent = parent
    ast.symbols = {}
    ast.types = {}
end

local function enter_scope(ast, env)
    local parent = env.scope
    if parent ~= ast then
        init_scope(ast, parent)
        env.scope = ast
    end
end

local function leave_scope(ast, env)
    env.scope = ast.parent
end

--------------------------------

local F = {}

function F:Block(ast, env, walk_node)
    enter_scope(ast, env)
    walk_node(self, ast)
    leave_scope(ast, env)
end

-- 把 scope 设在 NameList 上
function F:FunctionDef(ast, env, walk_node)
    assert(ast[1].tag == 'FuncName')
    assert(ast[2].tag == 'NameList')
    assert(ast[3].tag == 'Block')

    self(ast[1])

    enter_scope(ast[2], env)
    self(ast[2])
    ast[3].scope = env.scope
    for i = 1, #ast[3] do
        self(ast[3][i])
    end
    leave_scope(ast[2], env)
end

-- 把 scope 设在 NameList 上
function F:LocalFunctionDef(ast, env, walk_node)
    assert(ast[1].tag == 'Id')
    assert(ast[2].tag == 'NameList')
    assert(ast[3].tag == 'Block')

    self(ast[1])

    enter_scope(ast[2], env)
    self(ast[2])
    ast[3].scope = env.scope
    for i = 1, #ast[3] do
        self(ast[3][i])
    end
    leave_scope(ast[2], env)
end

--------------------------------

local function walk_func(walker, ast, env, walk_node)
    ast.scope = env.scope

    local f = F[ast.tag]
    if f then
        return f(walker, ast, env, walk_node)
    else
        return walk_node(walker, ast)
    end
end

--------------------------------

return function(ast)

    -- env.scope 总是指向当前代表 scope 的 ast 节点
    local env = {
        scope = ast,
    }
    init_scope(ast, nil)

    local walker = Walk(walk_func, env)
    walker(ast)
end
