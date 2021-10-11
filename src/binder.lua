-- luacheck: ignore 212

local Parser = require('parser')
local Types = require('types')
local Walk = require('walk')

local sf = string.format
local TYPE_NAME2ID = Types.TYPE_NAME2ID

--------------------------------

local function ast_error(ast, fmt, ...)
    local info = ast and ast.info or {}
    print(sf('%s:%d: ' .. fmt, info.filename or '?', info.line or 0, ...))
end

local function find_symbol(ast, name)
    local scope = ast.scope
    while scope do
        local si = scope.symbols[name]
        if si then
            return si
        end
        scope = scope.parent
    end
    return nil
end

--local function typeinfo_split(ast)
--    if ast.tag == 'TypeArrow' then
--        return ast[1], ast[2]
--    else
--        return ast, nil
--    end
--end

--------------------------------

local function init_scope(ast, parent)
    ast.parent = parent
    ast.symbols = {}
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

local function convert_type(ast)
    if ast.tag == 'TypeFunction' then
        return { tag='TypeFunction', info=ast.info, convert_type(ast[1]), convert_type(ast[2]) }
    elseif ast.tag == 'Id' then
        local typename = ast[1]

        -- 基础类型
        local id = TYPE_NAME2ID[typename]
        if id then
            return { tag='Id', info=ast.info, id }
        end

        -- 自定义类型
        local si = find_symbol(ast, typename)
        if not si then
            ast_error(ast, 'unknown type: %s', typename)
        end

        -- si 可能为 nil
        return { tag='TypeAlias', typename, si }

    elseif ast.tag == 'VarArg' then
        return { tag='VarArg', info=ast.info }
    elseif ast.tag == 'TypeArgList' then
        local nn = { tag='TypeArgList', info=ast.info}
        for i = 1, #ast do
            nn[i] = convert_type(ast[i])
        end
        return nn
    elseif ast.tag == 'TypeObj' then
        local nn = { tag='TypeObj', info=ast.info }
        for i = 1, #ast, 2 do
            nn[i] = ast[i]
            nn[i+1] = convert_type(ast[i+1])
        end
        return nn
    else
        error('unknown type node tag: ' .. ast.tag)
    end
end

-- TODO: 区分 Tpdef 和 Tpbind
function F:Tpdef(ast, env, walk_node)
    walk_node(self, ast)

    local n_id      = ast[1]
    local n_type    = ast[2]
    local symbols = env.scope.symbols
    symbols[n_id[1]] = convert_type(n_type)
end

function F:Tpbind(ast, env, walk_node)
    walk_node(self, ast)

    local n_id      = ast[1]
    local n_type    = ast[2]
    local symbols = env.scope.symbols
    symbols[n_id[1]] = convert_type(n_type)
end

--function F.LocalFunctionDef(ast, env)
--    local n_funcname    = ast[1]
--    local n_parlist     = ast[2]
--    local n_block       = ast[3]
--
--    local funcname = n_funcname[1]
--    local symbols = ast.scope.symbols
--    local si = symbols[funcname]
--    if si then
--        local t_rest = si
--        local t_ret = nil
--        local t_cur
--
--        -- match parlist
--        for _ = 1, #n_parlist do
--            t_cur, t_ret = typeinfo_split(t_rest)
--            if t_cur.tag ~= 'VarArg' then
--                t_rest = t_ret
--            end
--        end
--
--        si.rettype = t_ret
--    else
--        -- 找不到，就自己构造一个
--        -- FIXME
--        local vararg = { tag='VarArg', info=ast.info }
--        local any = { tag='Id', info=ast.info, 'Any' }
--        symbols[funcname] = { tag='TypeArrow', info=ast.info, rettype=any, vararg, any }
--    end
--
--    walk(env, n_block)
--end

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

local BUILTIN = [[
-->> print = ... >> void;
]]

local function init_global_symbols(symbols)
    local ast = Parser(BUILTIN, 'BUILTIN')
    local env = {
        scope = ast,
    }
    init_scope(ast, nil)
    ast.symbols = symbols
    local walker = Walk(walk_func, env)
    walker(ast)
end

--------------------------------

return function(ast)
    -- env.scope 总是指向当前代变 scope 的 ast 节点
    local env = {
        scope = ast,
    }
    init_scope(ast, nil)

    init_global_symbols(ast.symbols)

    local walker = Walk(walk_func, env)
    walker(ast)
end
