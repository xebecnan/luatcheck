local Walk = require('walk')
local Types = require('types')
local Symbols = require('symbols')
local Util = require 'util'

local TYPE_NAME2ID = Types.TYPE_NAME2ID
local sf = string.format
local ast_error = Util.ast_error

local function find_id_symbol_or_type(scope_field, ast)
    assert(ast.tag == 'Id')
    local scope = ast.scope
    local name = ast[1]
    while scope do
        local si = scope[scope_field][name]
        if si then
            return si
        end
        scope = scope.parent
    end
    return nil
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
        local ti = Symbols.find_type(ast)
        if not ti then
            ast_error(ast, 'unknown type: %s', typename)
        end

        return { tag='TypeAlias', typename, ti }

    elseif ast.tag == 'VarArg' then
        return { tag='VarArg', info=ast.info }
    elseif ast.tag == 'TypeArgList' then
        local nn = { tag='TypeArgList', info=ast.info}
        for i = 1, #ast do
            nn[i] = convert_type(ast[i])
        end
        return nn
    elseif ast.tag == 'TypeObj' then
        local keys = ast.keys
        local hash = ast.hash
        local nn = { tag='TypeObj', info=ast.info, keys=keys, hash=hash, open=ast.open }
        for _, k in ipairs(keys) do
            hash[k] = convert_type(hash[k])
        end
        -- for i = 1, #ast, 2 do
        --     nn[i] = ast[i]
        --     nn[i+1] = convert_type(ast[i+1])
        -- end
        return nn
    -- elseif ast.tag == 'CloseTypeObj' then
    --     return { tag='CloseTypeObj', info=ast.info }
    elseif ast.tag == 'OptArg' then
        return { tag='OptArg', info=ast.info, convert_type(ast[1]) }
    else
        error('unknown type node tag: ' .. ast.tag)
    end
end

--------------------------------

local F = {}

function F:Tpdef(ast, env, walk_node)
    walk_node(self, ast)

    local n_id      = ast[1]
    local n_type    = ast[2]
    Symbols.set_type(n_id, convert_type(n_type))
end

function F:Tpbind(ast, env, walk_node)
    walk_node(self, ast)

    local n_id      = ast[1]
    local n_type    = ast[2]
    Symbols.set_var(n_id, convert_type(n_type))
end

function F:LocalFunctionDef(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_parlist     = ast[2]

    local si = Symbols.find_var(n_funcname)
    if si then
        assert(si.tag == 'TypeFunction')
        local par_types = si[1]

        -- match parlist
        local i = 1
        local error_flag = false
        for _ = 1, #n_parlist do
            local n_type = par_types[i]
            if not n_type then
                ast_error(ast, 'redundant arg #%d', i)
                error_flag = true
                break
            end
            local n_par = n_parlist[i]
            if n_par.tag ~= 'VarArg' then
                Symbols.set_var(n_par, n_type)
            end
            if n_type.tag ~= 'VarArg' then
                i = i + 1
            end
        end

        if not error_flag and i <= #par_types then
            local n_type = par_types[i]
            if n_type.tag ~= 'VarArg' then
                ast_error(ast, 'missing arg #%d (%s)', i, Types.get_full_type_name(n_type))
            end
        end
    end

    walk_node(self, ast)
end

--------------------------------

local function walk_func(walker, ast, env, walk_node)
    local f = F[ast.tag]
    if f then
        return f(walker, ast, env, walk_node)
    else
        return walk_node(walker, ast)
    end
end

--------------------------------

return function(ast)
    local env = { }
    local walker = Walk(walk_func, env)
    walker(ast)
end
