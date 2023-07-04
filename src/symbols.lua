local Util = require 'util'

local ast_error = Util.ast_error
local dump_table = Util.dump_table
local sf = string.format
local errorf = function(...)
    error(sf(...))
end

local M  = {}

local function resolve_si(t, name, si, narrow_func)
    if si.tag == 'TypeOfExpr' then
        -- expand lazy node
        local Types = require('types')
        si = Types.get_node_type(si[1])
        if si then
            if si.tag == 'Id' and si[1] == 'Nil' then
                si = { tag='Id', 'Any' }
            end
            t[name] = si
        end
    end
    if si and si.tag == 'Id' and si[1] == 'Any' and narrow_func then
        si = narrow_func(si)
        t[name] = si
    end
    return si
end

local function find_id_symbol_aux(namespace, scope, name, narrow_func)
    local si
    local raw_scope = scope
    while scope do
        local t = scope.symbols[namespace] or errorf('bad namespace: %s', namespace)
        si = t[name]
        if si then
            return resolve_si(t, name, si, narrow_func)
        end
        scope = scope.parent
    end
    if narrow_func then
        si = narrow_func(nil)
    else
        si = { tag='Id', 'Any' }
    end
    raw_scope.symbols[namespace][name] = si
    return si
end

local function narrow_to_type_obj(si)
    local keys = {}
    local hash = {}
    -- open 表示当前状态下这个 table 是可以往里面添加字段的
    -- partial 表示并不知道 table 的完整信息，假设可能存在我们不知道的字段
    return { tag='TypeObj', info=(si and si.info), keys=keys, hash=hash, open=true, partial=not si }
end

local function get_table_field(si, key)
    local field_type = si.hash[key]
    if field_type then
        return field_type
    end

    -- partial 表示并不知道 table 的完整信息，假设可能存在我们不知道的字段
    if si.partial then
        return { tag='Id', 'Any' }
    end

    return nil
end

local set_symbol

local function find_symbol(namespace, ast, narrow_func)
    local t = ast.scope.symbols[namespace] or errorf('bad namespace: %s', namespace)
    local ns = t['__next_symbol__']
    if ns then
        t['__next_symbol__'] = nil
        set_symbol(namespace, ast, ns)
        return ns
    end

    if ast.tag == 'Id' then
        return find_id_symbol_aux(namespace, ast.scope, ast[1], narrow_func)
    end

    if ast.tag == 'IndexShort' or ast.tag == 'Invoke' then
        assert(ast[2].tag == 'Id')
        local si1 = find_symbol(namespace, ast[1], nil)
        if si1 then
            if si1.tag == 'Id' and si1[1] == 'Any' then
                return { tag='Id', 'Any' }
            end
            if si1.tag == 'TypeObj' then
                local n = ast[2]
                assert(n.tag == 'Id')
                local key = n[1]
                return get_table_field(si1, key)
            else
                -- TODO: 也可能是 string 或其他有 __index metamethod 的东西
                -- ast_error(ast, "index a non-table value")
                return { tag='Id', 'Any' }
            end
        else
            return { tag='Id', 'Any' }
        end
    end

    if ast.tag == 'Index' then
        local si1 = find_symbol(namespace, ast[1], nil)
        if not si1 then
            return { tag='Id', 'Any' }
        end
        if si1.tag == 'Id' and si1[1] == 'Any' then
            return { tag='Id', 'Any' }
        end
        if si1.tag ~= 'TypeObj' then
            -- TODO: 也可能是 string 或其他有 __index metamethod 的东西
            -- ast_error(ast, "index a non-table value")
            return { tag='Id', 'Any' }
        end

        -- literal string / literal integer
        if ast[2].tag == 'Str' then
            local key = ast[2][1]
            return get_table_field(si1, key)
        elseif ast[2].tag == 'Integer' then
            local key = ast[2][1]
            return get_table_field(si1, key)
        end

        local Types = require('types')
        local field_type = Types.get_node_type(ast[2])
        if field_type.tag == 'Id' and field_type[1] == 'Any' then
            return { tag='Id', 'Any' }
        else
            -- TODO: 其他类型作为 key, 之后可以支持按类型索引
            -- ast_error(ast, "find_symbol not support '%s' yet: TODO", Types.get_full_type_name(field_type, false))
            return { tag='Id', 'Any' }
        end
    elseif ast.tag == 'FuncName' then
        if #ast >= 2 then
            assert(ast[1].tag == 'Id')
            local tt = find_symbol(namespace, ast[1], narrow_to_type_obj)
            for i = 2, #ast do
                assert(ast[i].tag == 'Id')
                local field = ast[i][1]
                tt = tt.hash[field]
                if not tt then
                    return { tag='Id', 'Any' }
                end
            end
            return tt
        elseif #ast >= 1 then
            assert(ast[1].tag == 'Id')
            return find_symbol(namespace, ast[1], nil)
        else
            errorf('bad funcname data. ast: %s', dump_table(ast))
        end
    elseif ast.tag == 'Call' then
        local si = M.find_var(ast[1])
        if si.tag == 'Id' and si[1] == 'Any' then
            return { tag='Id', 'Any' }
        elseif si.tag == 'TypeFunction' then
            return si[2] or errorf('symbol info error. funcname: %s', dump_table(ast[1]))
        else
            ast_error(ast, 'find_symbol bad si tag: %s', si.tag)
            return { tag='Id', 'Any' }
        end
    elseif ast.tag == 'Block' then
        return find_id_symbol_aux(namespace, ast, '__return__', nil)
    elseif ast.tag == 'Function' then
        local si = find_id_symbol_aux(namespace, ast.scope, ast, nil)
        if si then
            return si
        end

        local n_parlist = ast[1]
        local Types = require('types')
        return Types.inference_func_type(ast.info, n_parlist)
    else
        ast_error(ast, 'find_symbol not support tag: %s', ast.tag)
        return { tag='Id', 'Any' }
    end
end

set_symbol = function(namespace, ast, setval)
    if ast.tag == 'Id' then
        local t = ast.scope.symbols[namespace] or errorf('bad namespace: %s', namespace)
        local name = ast[1]
        local old_si = t[name]
        if old_si and not (old_si.tag == 'Id' and old_si[1] == 'Any') then
            ast_error(ast, "symbol '%s' is overwritten", name)
        end
        t[name] = setval
        return
    elseif ast.tag == 'IndexShort' or ast.tag == 'Invoke' then
        assert(ast[2].tag == 'Id')
        local si1 = find_symbol(namespace, ast[1], nil)
        if si1 then
            if si1.tag == 'Id' and si1[1] == 'Any' then
                return
            end
            if si1.tag ~= 'TypeObj' then
                ast_error(ast, "index a non-table value")
                return
            end
            local name = ast[2][1]
            local old_si = si1.hash[name]
            if old_si and not (old_si.tag == 'Id' and old_si[1] == 'Any') then
                ast_error(ast, "symbol '%s' is overwritten", name)
            end
            si1.hash[name] = setval
            return
        else
            return
        end
    elseif ast.tag == 'Index' then
        local si1 = find_symbol(namespace, ast[1], narrow_to_type_obj)
        if si1.tag == 'Id' and si1[1] == 'Any' then
            return
        end
        if si1.tag ~= 'TypeObj' then
            -- TODO: 也可能是 string 或其他有 __index metamethod 的东西
            -- ast_error(ast, "index a non-table value")
            return
        end

        -- literal string / literal integer
        if ast[2].tag == 'Str' then
            local key = ast[2][1]
            si1.hash[key] = setval
            return
        elseif ast[2].tag == 'Integer' then
            local key = ast[2][1]
            si1.hash[key] = setval
            return
        end

        -- TODO: 暂时无法处理 key 是复杂表达式的情况
        return
    elseif ast.tag == 'FuncName' then
        if #ast >= 2 then
            assert(ast[1].tag == 'Id')
            local tt = find_symbol(namespace, ast[1], nil)
            local obj
            local field = nil
            local next_obj = tt
            for i = 2, #ast do
                assert(ast[i].tag == 'Id')
                obj = next_obj
                field = ast[i][1]
                if not obj then
                    return
                end
                next_obj = obj.hash[field]
            end
            obj.hash[field] = setval
        elseif #ast >= 1 then
            return set_symbol(namespace, ast[1], setval)
        else
            errorf('bad funcname data. ast: %s', dump_table(ast))
        end
    elseif ast.tag == 'Block' then
        assert(ast.scope == ast)
        local t = ast.symbols[namespace]
        t['__return__'] = setval
    elseif ast.tag == 'Function' then
        local t = ast.scope.symbols[namespace]
        t[ast] = setval
    elseif ast.tag == 'RefToNextSymbol' then
        local t = ast.scope.symbols[namespace] or errorf('bad namespace: %s', namespace)
        t['__next_symbol__'] = setval
    else
        ast_error(ast, 'set_symbol not support tag: %s', ast.tag)
        return
    end
end

function M.find_type(ast)
    return find_symbol('types', ast, nil)
end

function M.find_var(ast)
    return find_symbol('vars', ast, nil)
end

function M.set_type(ast, val)
    set_symbol('types', ast, val)
end

function M.set_var(ast, val)
    set_symbol('vars', ast, val)
end

return M
