-- luacheck: ignore 212

local Types = require('types')
local Util = require 'util'
local Walk = require('walk')
-- local seri_func = require 'lib.serialize_lua'

local get_type_name = Types.get_type_name
local is_subtype_of = Types.is_subtype_of
local is_basetype = Types.is_basetype
local to_hash = Util.to_hash

local sf = string.format
local errorf = function(...)
    error(sf(...))
end

----

local RELA_OPR = { '==', '~=', '<', '>', '<=', '>=' }
local LOGI_OPR = { 'and', 'or', 'not' }
local BITW_OPR = { '&', '|', '~', '>>', '<<', '~' }
local ARIT_OPR = { '+', '-', '*', '/', '//', '%', '^'}

local IS_RELA_OPR = to_hash(RELA_OPR)
local IS_LOGI_OPR = to_hash(LOGI_OPR)
local IS_BITW_OPR = to_hash(BITW_OPR)
local IS_ARIT_OPR = to_hash(ARIT_OPR)

----

----[[>>
--AstNode = {
--    tag : string,
--    info : any,
--    scope : any,
--}
--<<]]
--
---->> ast_error = AstNode, string, ... >> void;
local function ast_error(ast, fmt, ...)
    local info = ast and ast.info or {}
    print(sf('%s:%d: ' .. fmt, info.filename or '?', info.line or 0, ...))
end

local function expect_node(node, tag)
    if node.tag ~= tag then
        ast_error(node, 'expect ' .. tag .. ' node, but given: ' .. node.tag)
    end
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

local function dump_table(t)
    if type(t) == 'table' then
        local b = {}
        b[#b+1] = '{'
        for k, v in pairs(t) do
            b[#b+1] = sf('%s=%s,', k, v)
        end
        b[#b+1] = '}'
        return table.concat(b, ' ')
    else
        return tostring(t)
    end
end

----

local function get_node_type_impl(ast)
    if is_basetype(ast.tag) then
        if ast.tag == 'Table' then
            return { tag='TypeTableProxy', info=ast.info, ast }
        end

        return { tag='Id', ast.tag, ast }

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
                elseif is_subtype_of(t1[1], 'Number') and is_subtype_of(t2[1], 'Number') then
                    return { tag='Id', 'Float' }
                end
            end

            ast_error(ast, sf('get_node_type of arith opr error. t1:%s t2:%s', dump_table(t1), dump_table(t2)))
            return nil
        else
            ast_error(ast, sf('get_node_type error. bad BinOpr: %s', op))
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
            ast_error(ast, sf('get_node_type error. bad UnOpr: %s', op))
            return nil
        end
    elseif ast.tag == 'Call' then
        local funcname = ast[1][1]
        local si = find_symbol(ast, funcname)
        if si then
            if si.tag ~= 'TypeFunction' then
                ast_error(ast, sf('get_node_type. bad si tag: %s', si.tag))
            else
                return si[2] or errorf('symbol info error. funcname: %s', funcname)
            end
        else
            return { tag='Id', 'Any' }
        end
    elseif ast.tag == 'Id' then
        local sname = ast[1]
        local si = find_symbol(ast, sname)
        -- print(sf('sname: %s si: %s scope:%s', sname, si, ast.scope))
        return si or { tag='Id', 'Any' }
    elseif ast.tag == 'IndexShort' then
        -- TODO
        return { tag='Id', 'Any' }
    elseif ast.tag == 'Index' then
        -- TODO
        return { tag='Id', 'Any' }
    elseif ast.tag == 'Function' then
        -- TODO
        return { tag='Id', 'Any' }
    else
        ast_error(ast, 'get_node_type not support: ' .. tostring(ast.tag))
        return nil
    end
end

local function get_node_type(ast)
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

----

local F = {}

function F:FunctionDef(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_parlist     = ast[2]

    local funcname = n_funcname[1]
    local si = find_symbol(ast, funcname)
    if si then
        local tp = si

        -- match parlist
        for i = 1, #n_parlist do
            local v = n_parlist[i]
            if v.tag == 'Id' then
                local name = v[1]
                expect_node(tp, 'TypeArrow')
                local n1 = tp[1]
                local n2 = tp[2]
                n1.varname = name
                tp = n2
            elseif v.tag == 'VarArg' then
                error('TODO')
            else
                error('parlist error')
            end
        end

        si.rettype = tp
    end

    walk_node(self, ast)
end

local match_type

function F:Local(ast, env, walk_node)
    walk_node(self, ast)

    local n_namelist = ast[1]
    local n_explist = ast[2]
    for  i = 1, #n_namelist do
        local n_name = n_namelist[i]
        local n_exp = n_explist[i]
        if n_exp then
            local given_type = get_node_type(n_exp)
            if given_type then
                local expect_type = find_symbol(ast, n_name[1]) or { tag='Id', 'Any' }
                local ok, err = match_type(expect_type, given_type)
                if not ok then
                    ast_error(ast, err)
                end
            end
        end
    end
end

local function match_func_type(expect, given)
    local arg1 = expect[1]
    local arg2 = given[1]
    local ret1 = expect[2]
    local ret2 = given[2]
    if #arg1 ~= #arg2 then
        return false
    end
    for i = 1, #arg1 do
        if not match_type(arg1[i], arg2[i]) then
            return false
        end
    end
    if not match_type(ret1, ret2) then
        return false
    end
    return true
end

local get_full_type_name

local function dump_type_obj(ast)
    local b = {}
    b[#b+1] = '{'
    for i = 1, #ast, 2 do
        local n_fieldname = ast[i]
        local n_fieldtype = ast[i+1]
        assert(n_fieldname.tag == 'Id')
        b[#b+1] = ' '
        b[#b+1] = n_fieldname[1]
        b[#b+1] = ':'
        b[#b+1] = get_full_type_name(n_fieldtype)
        if i < #ast - 1 then
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
        b[#b+1] = get_full_type_name(get_node_type(nv))
        if i < #ast - 1 then
            b[#b+1] = ';'
        end
    end
    b[#b+1] = ' }'
    return table.concat(b, '')
end

get_full_type_name = function(ast)
    if ast.tag == 'Id' then
        return get_type_name(ast[1])
    elseif ast.tag == 'TypeFunction' then
        local b = {}
        for i = 1, #ast[1] do
            b[#b+1] = get_full_type_name(ast[1][i])
            if i ~= #ast[1] then
                b[#b+1] = ', '
            end
        end
        b[#b+1] = ' >> '
        b[#b+1] = get_full_type_name(ast[2])
        return table.concat(b, '')
    elseif ast.tag == 'TypeAlias' then
        return ast[1]
    elseif ast.tag ==  'TypeObj' then
        return dump_type_obj(ast)
    elseif ast.tag == 'TypeTableProxy' then
        return dump_type_table(ast[1])
    else
        error(sf('get_full_type_name error: %s', dump_table(ast)))
    end
end

local function match_table(expect, given)
    local og = {}  -- Only in Given
    local oe = {}  -- Only in Expect
    local matched = true

    -- 'TypeTableProxy
    local given_ast = given[1]
    for i = 1, #given_ast, 2 do
        local nk = given_ast[i]
        local nv = given_ast[i+1]
        if nk.tag == 'Integer' then
            og[nk[1]] = nv
        elseif nk.tag == 'Id' then
            og[nk[1]] = nv
        else
            ast_error(nk, 'cannot determin the type of key')
        end
    end

    -- 'TypeObj
    for i = 1, #expect, 2 do
        local n_fieldname = expect[i]
        local n_fieldtype = expect[i+1]
        assert(n_fieldname.tag == 'Id')
        local k = n_fieldname[1]
        local to_match = og[k]
        if to_match then
            og[k] = nil
            local to_match_type = get_node_type(to_match)
            local ok, _ = match_type(n_fieldtype, to_match_type)
            if not ok then
                matched = false
                -- ast_error(to_match, err)
            end
        else
            oe[k] = n_fieldtype
        end
    end

    return matched and not next(og) and not next(oe)
end

match_type = function(expect, given)
    -- 对 any 类型的变量不作检查, any 可以匹配任意类型
    if expect.tag == 'Id' and expect[1] == 'Any' then
        return true
    end

    if expect.tag == 'Id' and given.tag == 'Id' then
        if is_subtype_of(given[1], expect[1]) then
            return true
        end
    elseif expect.tag == 'VarArg' then
        return true
    elseif given.tag == 'TypeFunction' then
        if expect.tag == 'TypeFunction' then
            if match_func_type(expect, given) then
                return true
            end
        end
    elseif given.tag == 'TypeTableProxy' then
        if expect.tag == 'TypeObj' then
            if match_table(expect, given) then
                return true
            end
        end
    end
    return false, sf('expect "%s", but given "%s"', get_full_type_name(expect), get_full_type_name(given))
end

local function match_node_type(node, tp)
    local node_type = get_node_type(node)
    if node_type then
        return match_type(tp, node_type)
    else
        return true
    end
    -- if tp.tag == 'Id' then
    -- elseif tp.tag == 'VarArg' then
    --     return true
    -- elseif tp.tag == 'TypeFunction' then
    --     local node_type = get_node_type(node)
    --     print('tp:', dump_table(tp))
    --     print('node:', dump_table(node))
    --     print('node_type:', dump_table(node_type))
    --     if node_type then
    --         return match_type(tp, node_type)
    --     else
    --         return true
    --     end
    -- else
    --     error('TODO tag: ' .. tp.tag)
    -- end
end

function F:Call(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_parlist     = ast[2]

    local funcname = n_funcname[1]
    local si = find_symbol(ast, funcname)
    if not si then
        -- return ast_error(ast, 'cannot find type info for: %s', funcname)
        return
    end

    if si.tag ~= 'TypeFunction' then
        error(sf("expect 'TypeFunction', but given '%s'", si.tag))
    end

    local n_args = si[1]
    -- local n_ret = si[2]

    local j = 1
    for i = 1, #n_parlist do
        local arg_given = n_parlist[i]
        local arg_expet = n_args[j]
        local ok, err = match_node_type(arg_given, arg_expet)
        if not ok then
            ast_error(ast, err)
        end

        if arg_expet.tag ~= 'VarArg' then
            j = j + 1
        end
    end

    walk_node(self, ast)
end

local function check_assign(env, ast1, ast2)
    -- TODO
end

function F:Set(ast, env, walk_node)
    local n1 = #ast[1]
    local n2 = #ast[2]
    local n = n1 > n2 and n1 or n2
    for i = 1, n do
        local ast1 = ast[1][i]
        local ast2 = ast[2][i]
        if ast1 and ast2 then
            check_assign(env, ast1, ast2)
        end
    end

    walk_node(self, ast)
end

--------------------------------------------------

local function walk_func(walker, ast, env, walk_node)
    local f = F[ast.tag]
    if f then
        return f(walker, ast, env, walk_node)
    else
        return walk_node(walker, ast)
    end
end

return function(ast)
    local env = { }
    local walker = Walk(walk_func, env)
    walker(ast)
end
