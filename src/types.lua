local Util = require 'util'
local Symbols = require 'symbols'
local Requirer = require 'requirer'

local to_hash = Util.to_hash
local ast_error = Util.ast_error
local dump_table = Util.dump_table

local sf = string.format
local errorf = function(...)
    error(sf(...))
end

local M = {}

local TYPE_DEF = {
    Any = { name='any' },
    Nil = { name='nil', parent='Any' },
    Void = { name='void', parent='Any' },
    Bool = { name='boolean', parent='Any' },
    Udata = { name='userdata', parent='Any' },
    Number = { name='number', parent='Any' },
    Integer = { name='integer', parent='Number' },
    Float = { name='float', parent='Number' },
    Str = { name='string', parent='Any' },
    Table = { name='table', parent='Any' },
    Never = { name='never', parent='__ALL_TYPES__' },
}

local TYPE_NAME2ID = {}
for id, v in pairs(TYPE_DEF) do
    TYPE_NAME2ID[v.name] = id
end
M.TYPE_NAME2ID = TYPE_NAME2ID

local RELA_OPR = { '==', '~=', '<', '>', '<=', '>=' }
local LOGI_OPR = { 'and', 'or', 'not' }
local BITW_OPR = { '&', '|', '~', '>>', '<<', '~' }
local ARIT_OPR = { '+', '-', '*', '/', '//', '%', '^'}

local IS_RELA_OPR = to_hash(RELA_OPR)
local IS_LOGI_OPR = to_hash(LOGI_OPR)
local IS_BITW_OPR = to_hash(BITW_OPR)
local IS_ARIT_OPR = to_hash(ARIT_OPR)

function M.get_type_name(t)
    local v = TYPE_DEF[t] or errorf('unknown type: %s', t)
    return v.name
end

function M.is_bottom_type(t)
    local v = TYPE_DEF[t] or errorf('unknown type: %s', t)
    return v.parent == '__ALL_TYPES__'
end

-- t1 是 t2 的子类型
function M.is_subtype_of(t1, t2)
    if M.is_bottom_type(t1) then
        return true
    end

    local p = t1
    while p do
        if t2 == p then
            return true
        end
        local v = TYPE_DEF[p] or errorf('unknown type: %s', p)
        p = v.parent
    end
    return false
end

function M.is_basetype(t)
    return not not TYPE_DEF[t]
end

--------------------------------
local get_node_type_impl

local function build_typetable(ast)
    assert(ast.tag == 'Table')
    local keys = {}
    local hash = {}
    local n_tpobj = { tag='TypeObj', info=ast.info, keys=keys, hash=hash, open=false }
    for i = 1, #ast, 2 do
        local nk = ast[i]
        local nv = ast[i+1]
        if nk.tag == 'Integer' or nk.tag == 'Id' then
            local k = nk[1]
            keys[#keys+1] = k
            hash[k] = get_node_type_impl(nv)
        end
    end
    return n_tpobj
end

get_node_type_impl = function(ast)
    if M.is_basetype(ast.tag) then
        if ast.tag == 'Table' then
            return build_typetable(ast)
        end

        return { tag='Id', ast.tag }

    elseif ast.tag == 'BinOpr' then
        local op = ast[1]
        if IS_RELA_OPR[op] then
            return { tag='Id', 'Bool' }
        elseif IS_LOGI_OPR[op] then
            return get_node_type_impl(ast[3])
        elseif IS_BITW_OPR[op] then
            return { tag='Id', 'Integer' }
        elseif IS_ARIT_OPR[op] then
            if op == '^' or op == '/' then
                return { tag='Id', 'Float' }
            end

            local t1 = get_node_type_impl(ast[2])
            local t2 = get_node_type_impl(ast[3])
            if not t1 or not t2 then
                return nil
            end

            if t1.tag == 'Id' and t2.tag == 'Id' then
                if t1[1] == 'Any' or t2[1] == 'Any' then
                    return { tag='Id', 'Any' }
                end

                if t1[1] == 'Integer' and t2[1] == 'Integer' then
                    return { tag='Id', 'Integer' }
                elseif M.is_subtype_of(t1[1], 'Number') and M.is_subtype_of(t2[1], 'Number') then
                    return { tag='Id', 'Float' }
                end
            end

            ast_error(ast, 'get_node_type of arith opr error. t1:%s t2:%s', dump_table(t1), dump_table(t2))
            return nil
        elseif op == '..' then
            return { tag='Id', 'Str' }
        else
            ast_error(ast, 'get_node_type error. bad BinOpr: %s', op)
            return nil
        end
    elseif ast.tag == 'UnOpr' then
        local op = ast[1]
        if IS_LOGI_OPR[op] then
            return { tag='Id', 'Bool' }
        elseif IS_BITW_OPR[op] then
            return { tag='Id', 'Integer' }
        elseif IS_ARIT_OPR[op] then
            return get_node_type_impl(ast[2])
        elseif op == '#' then  -- Length Operator
            return { tag='Id', 'Integer' }
        else
            ast_error(ast, 'get_node_type error. bad UnOpr: %s', op)
            return nil
        end
    elseif ast.tag == 'Call' then
        local si = Symbols.find_var(ast[1])
        if not si then
            -- called a nil value
            return { tag='Id', 'Any' }
        elseif si.tag == 'TypeFunction' then
            -- require 函数
            local require_path = ast.require_path
            if require_path then
                local rinfo = Requirer(require_path)
                return rinfo.require_type
            end

            -- 普通函数
            return si[2]
        elseif si.tag == 'Id' and si[1] == 'Any' then
            return { tag='Id', 'Any' }
        else
            ast_error(ast, 'bad function symbol info: %s', si.tag)
            return { tag='Id', 'Any' }
        end
    elseif ast.tag == 'Id' then
        return Symbols.find_var(ast)
    elseif ast.tag == 'IndexShort' then
        -- TODO
        return { tag='Id', 'Any' }
    elseif ast.tag == 'Index' then
        -- TODO
        return { tag='Id', 'Any' }
    elseif ast.tag == 'Function' then
        return Symbols.find_var(ast)
    elseif ast.tag == 'VarArg' then
        return { tag='VarArg', info=ast.info }
    else
        ast_error(ast, 'get_node_type not support: ' .. tostring(ast.tag))
        return { tag='Id', 'Any' }
    end
end

function M.get_node_type(ast)
    local msgh = function(s)
        local s1, s2, s3 = s:match('^([^:]*):(%d+): (.*)$')
        return debug.traceback(string.format('(%s:%d) %s', s1, s2, s3))
    end
    local ok, val = xpcall(get_node_type_impl, msgh, ast)
    if not ok then
        ast_error(ast, val)
        return nil
    end
    return val
end

--------------------------------

function M.inference_func_type(info, n_parlist)
    local n_partypes = { tag='TypeArgList', info=n_parlist.info }
    for i = 1, #n_parlist do
        local n_par = n_parlist[i]
        if n_par.tag == 'VarArg' then
            n_partypes[#n_partypes+1] = { tag='VarArg', info=n_par.info }
        elseif n_par.tag == 'Id' then
            n_partypes[#n_partypes+1] = { tag='Id', parname=n_par[1], 'Any' }
        else
            errorf('bad parameter tag: %s', n_par.tag)
        end
    end
    local n_ret = { tag='Id', 'Any' }
    return { tag='TypeFunction', info=info, n_partypes, n_ret }
end

--------------------------------

local function dump_type_obj(ast)
    local keys = ast.keys
    local hash = ast.hash
    local b = {}
    b[#b+1] = '{'
    for i = 1, #keys do
        local k = keys[i]
        local n_fieldtype = hash[k]
        b[#b+1] = ' '
        b[#b+1] = k
        b[#b+1] = ':'
        b[#b+1] = M.get_full_type_name(n_fieldtype, false)
        if i < #ast then
            b[#b+1] = ';'
        end
    end
    b[#b+1] = ' }'
    return table.concat(b, '')
end

local function dump_type_table(ast)
    local b = {}
    b[#b+1] = '{'
    for i = 1, #ast, 2 do
        local nk = ast[i]
        local nv = ast[i+1]
        b[#b+1] = ' '
        if nk.tag == 'Id' then
            b[#b+1] = nk[1]
        elseif nk.tag == 'Integer' then
            b[#b+1] = sf('[%d]', nk[1])
        else
            b[#b+1] = '[?]'
        end
        b[#b+1] = ':'
        b[#b+1] = M.get_full_type_name(M.get_node_type(nv), false)
        if i < #ast - 1 then
            b[#b+1] = ';'
        end
    end
    b[#b+1] = ' }'
    return table.concat(b, '')
end

local function get_full_type_name_aux(ast, with_par_name)
    if ast.tag == 'Id' then
        return M.get_type_name(ast[1])
    elseif ast.tag == 'TypeFunction' then
        local b = {}
        if ast.is_require then
            b[#b+1] = '(require) '
        end
        for i = 1, #ast[1] do
            b[#b+1] = M.get_full_type_name(ast[1][i], false)
            if i ~= #ast[1] then
                b[#b+1] = ', '
            end
        end
        b[#b+1] = ' >> '
        b[#b+1] = M.get_full_type_name(ast[2], false)
        return table.concat(b, '')
    elseif ast.tag == 'TypeAlias' then
        return ast[1]
    elseif ast.tag ==  'TypeObj' then
        return dump_type_obj(ast)
    elseif ast.tag == 'TypeTableProxy' then
        return dump_type_table(ast[1])
    elseif ast.tag == 'VarArg' then
        return '...'
    -- elseif ast.tag == 'CloseTypeObj' then
    --     error
    else
        error(sf('get_full_type_name error: %s', dump_table(ast)))
    end
end

function M.get_full_type_name(ast, with_par_name)
    if with_par_name and ast.parname then
        return sf("%s (%s)", ast.parname, M.get_full_type_name(ast, false))
    end

    local s = get_full_type_name_aux(ast, with_par_name)
    if ast.is_opt then
        return s ..'?'
    else
        return s
    end
end

--------------------------------

return M
