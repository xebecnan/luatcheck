local Util = require 'util'

local ast_error = Util.ast_error
local dump_table = Util.dump_table
local sf = string.format
local errorf = function(...)
    error(sf(...))
end

local M  = {}

local function find_id_symbol_aux(namespace, scope, name)
    while scope do
        local t = scope.symbols[namespace] or errorf('bad namespace: %s', namespace)
        local si = t[name]
        if si then
            if si.tag == 'TypeOfExpr' then
                local Types = require('types')
                return Types.get_node_type(si[1])
            end
            return si
        end
        scope = scope.parent
    end
    return { tag='Id', 'Any' }
end

local function find_symbol(namespace, ast)
    if ast.tag == 'Id' then
        return find_id_symbol_aux(namespace, ast.scope, ast[1])
    elseif ast.tag == 'IndexShort' or ast.tag == 'Invoke' then
        assert(ast[2].tag == 'Id')
        local si1 = find_symbol(namespace, ast[1])
        if si1 then
            if si1.tag == 'Id' and si1[1] == 'Any' then
                return { tag='Id', 'Any' }
            end
            if si1.tag == 'TypeObj' then
                local n = ast[2]
                assert(n.tag == 'Id')
                local key = n[1]
                return si1.hash[key] or { tag='Id', 'Any' }
            else
                ast_error(ast, "index a non-table value")
                return { tag='Id', 'Any' }
            end
        else
            return { tag='Id', 'Any' }
        end
    elseif ast.tag == 'Index' then
        ast_error(ast, 'find_symbol not support <Index> yet: TODO')
        return { tag='Id', 'Any' }
    elseif ast.tag == 'FuncName' then
        assert(ast[1].tag == 'Id')
        local tt = find_symbol(namespace, ast[1])
        for i = 2, #ast do
            assert(ast[i].tag == 'Id')
            local field = ast[i][1]
            tt = tt.hash[field]
            if not tt then
                return { tag='Id', 'Any' }
            end
        end
        return tt
    elseif ast.tag == 'Call' then
        local si = M.find_var(ast[1])
        if si.tag ~= 'TypeFunction' then
            ast_error(ast, sf('get_node_type. bad si tag: %s', si.tag))
            return { tag='Id', 'Any' }
        end
        return si[2] or errorf('symbol info error. funcname: %s', dump_table(ast[1]))
    elseif ast.tag == 'Block' then
        return find_id_symbol_aux(namespace, ast, '__return__')

    else
        ast_error(ast, 'find_symbol not support tag: %s', ast.tag)
        return { tag='Id', 'Any' }
    end
end

local function set_symbol(namespace, ast, setval)
    if ast.tag == 'Id' then
        local name = ast[1]
        local t = ast.scope.symbols[namespace] or errorf('bad namespace: %s', namespace)
        if t[name] then
            ast_error(ast, "symbol '%s' is overwritten", name)
        end
        t[name] = setval
        return
    elseif ast.tag == 'IndexShort' or ast.tag == 'Invoke' then
        assert(ast[2].tag == 'Id')
        local si1 = find_symbol(namespace, ast[1])
        if si1 then
            if si1.tag == 'Id' and si1[1] == 'Any' then
                return
            end
            if si1.tag ~= 'TypeObj' then
                ast_error(ast, "index a non-table value")
                return
            end
            local name = ast[2][1]
            if si1.hash[name] then
                ast_error(ast, "symbol '%s' is overwritten", name)
            end
            si1.hash[name] = setval
            return
        else
            return
        end
    elseif ast.tag == 'Index' then
        ast_error(ast, 'find_symbol not support <Index> yet: TODO')
        return
    elseif ast.tag == 'FuncName' then
        ast_error(ast, "setting symbol value is not supported for 'FuncName' node")
    elseif ast.tag == 'Block' then
        assert(ast.scope == ast)
        local t = ast.symbols[namespace]
        t['__return__'] = setval
    else
        ast_error(ast, 'find_symbol not support tag: %s', ast.tag)
        return
    end
end

function M.find_type(ast)
    return find_symbol('types', ast)
end

function M.find_var(ast)
    return find_symbol('vars', ast)
end

function M.set_type(ast, val)
    set_symbol('types', ast, val)
end

function M.set_var(ast, val)
    set_symbol('vars', ast, val)
end

return M
