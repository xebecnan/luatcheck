-- luacheck: ignore 212

local Types = require('types')
local Util = require 'util'
local Walk = require('walk')

local get_type_name = Types.get_type_name
local is_subtype_of = Types.is_subtype_of
local is_basetype = Types.is_basetype
local to_hash = Util.to_hash
local dump_table = Util.dump_table
local TYPE_NAME2ID = Types.TYPE_NAME2ID

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

--[[>>
AstNode = {
    tag : string;
    info : any;
    scope : any;
}
<<]]

-->> ast_error = AstNode, string, ... >> void;
local function ast_error(ast, fmt, ...)
    local info = ast and ast.info or {}
    print(sf('%s:%d: ' .. fmt, info.filename or '?', info.line or 0, ...))
end

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

-- 找不到的话返回 nil
-->> find_symbol_or_type :: string, AstNode, boolean, any >> any
local function find_symbol_or_type(scope_field, ast, setflag, setval)
    if ast.tag == 'Id' then
        if setflag then
            local name = ast[1]
            if ast.scope[scope_field][name] then
                ast_error(ast, "symbol '%s' is overwritten", name)
            end
            ast.scope[scope_field][name] = setval
            return setval
        else
            return find_id_symbol_or_type(scope_field, ast)
        end
    elseif ast.tag == 'IndexShort' or ast.tag == 'Invoke' then
        assert(ast[2].tag == 'Id')
        local si1 = find_symbol_or_type(scope_field, ast[1])
        if si1 then
            if setflag then
                local name = ast[2][1]
                if si1.hash[name] then
                    ast_error(ast, "symbol '%s' is overwritten", name)
                end
                si1.hash[name] = setval
                return setval
            else
                return si1.hash[ast[2][1]]
            end
        else
            return nil
        end
    elseif ast.tag == 'Index' then
        ast_error(ast, 'find_symbol_or_type not support <Index> yet: TODO')
        return nil
    elseif ast.tag == 'FuncName' then
        if setflag then
            ast_error(ast, "setting symbol value is not supported for 'FuncName' node")
        end
        assert(ast[1].tag == 'Id')
        local tt = find_symbol_or_type(scope_field, ast[1])
        for i = 2, #ast do
            assert(ast[i].tag == 'Id')
            local field = ast[i][1]
            -- if setflag and i == #ast then
            --     tt.hash[field] = setval
            --     return setval
            -- end
            tt = tt.hash[field]
            if not tt then
                -- if setflag then
                --     ast_error(ast, 'symbol not found')
                -- end
                return nil
            end
        end
        return tt
    else
        ast_error(ast, 'find_symbol_or_type not support tag: %s', ast.tag)
        return nil
    end
end

local function find_type(ast, setflag, setval)
    return find_symbol_or_type('types', ast, setflag, setval)
end

local function find_symbol(ast, setflag, setval)
    return find_symbol_or_type('symbols', ast, setflag, setval)
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
        local si = find_symbol(ast[1])
        if si then
            if si.tag ~= 'TypeFunction' then
                ast_error(ast, sf('get_node_type. bad si tag: %s', si.tag))
            else
                return si[2] or errorf('symbol info error. funcname: %s', dump_table(ast[1]))
            end
        else
            return { tag='Id', 'Any' }
        end
    elseif ast.tag == 'Id' then
        local si = find_symbol(ast)
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
    elseif ast.tag == 'VarArg' then
        return { tag='VarArg', info=ast.info }
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
    -- local n_funcname    = ast[1]
    -- local n_parlist     = ast[2]

    -- local si = find_symbol(n_funcname)
    -- if si then
    --     -- local tp = si

    --     -- -- match parlist
    --     -- for i = 1, #n_parlist do
    --     --     local v = n_parlist[i]
    --     --     if v.tag == 'Id' then
    --     --         local name = v[1]
    --     --         expect_node(tp, 'TypeArrow')
    --     --         local n1 = tp[1]
    --     --         local n2 = tp[2]
    --     --         n1.varname = name
    --     --         tp = n2
    --     --     elseif v.tag == 'VarArg' then
    --     --         error('TODO')
    --     --     else
    --     --         error('parlist error')
    --     --     end
    --     -- end

    --     -- si.rettype = tp
    -- end

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
                local expect_type = find_symbol(n_name) or { tag='Id', 'Any' }
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
        b[#b+1] = get_full_type_name(n_fieldtype)
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
    elseif ast.tag == 'VarArg' then
        return '...'
    -- elseif ast.tag == 'CloseTypeObj' then
    --     error
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
    local keys = expect.keys
    local hash = expect.hash
    for _, k in ipairs(keys) do
        local n_fieldtype = hash[k]
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
    if given.tag == 'Id' and given[1] == 'Any' then
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
        elseif expect.tag == 'TypeAlias' then
            if match_type(expect[2], given) then
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

    local si = find_symbol(n_funcname)
    -- print('CALL', dump_table(n_funcname), '---->', dump_table(si))
    if not si then
        -- return ast_error(ast, 'cannot find type info for: %s', funcname)
        walk_node(self, ast)
        return
    end

    if si.tag ~= 'TypeFunction' then
        error(sf("expect 'TypeFunction', but given '%s'", si.tag))
    end

    local n_args = si[1]
    -- local n_ret = si[2]

    local j = 0
    local error_flag = false
    for i = 1, #n_parlist do
        local arg_given = n_parlist[i]
        local arg_expet = n_args[j+1]
        if not arg_expet then
            ast_error(ast, "redundant arg #%d (%s)", i, get_full_type_name(get_node_type(arg_given)))
            error_flag = true
            break
        end
        local ok, err = match_node_type(arg_given, arg_expet)
        if not ok then
            ast_error(ast, sf('arg #%d, %s', j+1, err))
            error_flag = true
            break
        end

        if arg_expet and arg_expet.tag ~= 'VarArg' then
            j = j + 1
        end
    end

    if not error_flag and j < #n_args then
        local arg_expet = n_args[j+1]
        if arg_expet.tag ~= 'VarArg' then
            ast_error(ast, "missing arg #%d (%s)", j+1, get_full_type_name(arg_expet))
        end
    end

    walk_node(self, ast)
end

--function F:Invoke(ast, env, walk_node)
--    print('aaaaaaaaaaaaaaaaaaaaa Invoke')
--    ast_error(ast, 'Invoke found')
--    walk_node(self, ast)
--end

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
        local ti = find_type(ast)
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
    else
        error('unknown type node tag: ' .. ast.tag)
    end
end

function F:Tpdef(ast, env, walk_node)
    walk_node(self, ast)

    local n_id      = ast[1]
    local n_type    = ast[2]
    find_type(n_id, true, convert_type(n_type))
end

function F:Tpbind(ast, env, walk_node)
    walk_node(self, ast)

    local n_id      = ast[1]
    local n_type    = ast[2]
    find_symbol(n_id, true, convert_type(n_type))
end

local function dump_typesuffixedname_aux(b, ast)
    if ast.tag == 'Id' then
        b[#b+1] = ast[1]
    elseif ast.tag == 'IndexShort' then
        assert(ast[2].tag == 'Id')
        dump_typesuffixedname_aux(b, ast[1])
        b[#b+1] = ast[2][1]
    else
        error('unknown type node tag: ' .. ast.tag)
    end
end

local function dump_typesuffixedname(ast)
    local b = {}
    dump_typesuffixedname_aux(b, ast)
    return table.concat(b, '.')
end

function F:OpenTypeObj(ast, env, walk_node)
    local si = find_symbol(ast[1])
    if not si then
        ast_error(ast, "open a non-existing table '%s'", dump_typesuffixedname(ast[1]))
    elseif si.open then
        ast_error(ast, "table '%s' already open", dump_typesuffixedname(ast[1]))
    else
        si.open = true
    end

    walk_node(self, ast)
end

function F:CloseTypeObj(ast, env, walk_node)
    local si = find_symbol(ast[1])
    if not si then
        ast_error(ast, "close a non-existing table '%s'", dump_typesuffixedname(ast[1]))
    elseif not si.open then
        ast_error(ast, "table '%s' already closed", dump_typesuffixedname(ast[1]))
    else
        si.open = false
    end

    walk_node(self, ast)
end

function F:LocalFunctionDef(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_parlist     = ast[2]

    local si = find_symbol(n_funcname)
    if si then
        assert(si.tag == 'TypeFunction')
        local n_args = si[1]

        -- match parlist
        local i = 1
        local error_flag = false
        for _ = 1, #n_parlist do
            local n_type = n_args[i]
            if not n_type then
                ast_error(ast, 'redundant arg #%d', i)
                error_flag = true
                break
            end
            find_symbol(n_parlist[i], true, n_type)
            if n_type.tag ~= 'VarArg' then
                i = i + 1
            end
        end

        if not error_flag and i <= #n_args then
            local n_type = n_args[i]
            if n_type.tag ~= 'VarArg' then
                ast_error(ast, 'missing arg #%d (%s)', i, get_full_type_name(n_type))
            end
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
