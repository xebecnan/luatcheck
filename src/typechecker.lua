-- luacheck: ignore 212

local Types = require('types')
local Util = require 'util'
local Walk = require('walk')
local Symbols = require('symbols')
local SerializeAst = require 'serialize_ast'

local get_type_name = Types.get_type_name
local is_subtype_of = Types.is_subtype_of
local is_basetype = Types.is_basetype
local dump_table = Util.dump_table

local sf = string.format
local errorf = function(...)
    error(sf(...))
end

----

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
            local expect_type = Symbols.find_var(n_name)
            local given_type = Types.get_node_type(n_exp)
            local ok, err = match_type(expect_type, given_type)
            if not ok then
                ast_error(ast, err)
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

local function match_table(expect, given)
    local only_in_given = {}  -- Only in Given

    -- 'TypeTableProxy
    if given.tag == 'TypeObj' then
        local keys = expect.keys
        local hash = expect.hash
        for _, k in ipairs(keys) do
            local n_fieldtype = hash[k]
            only_in_given[k] = n_fieldtype
        end
    elseif given.tag == 'TypeTableProxy' then
        local given_ast = given[1]
        for i = 1, #given_ast, 2 do
            local nk = given_ast[i]
            local nv = given_ast[i+1]
            if nk.tag == 'Integer' then
                only_in_given[nk[1]] = nv
            elseif nk.tag == 'Id' then
                only_in_given[nk[1]] = nv
            else
                ast_error(nk, 'cannot determin the type of key')
            end
        end
    else
        ast_error(expect, 'unknown table tag: %s', expect.tag)
        return false
    end

    if expect.tag == 'TypeObj' then
        local keys = expect.keys
        local hash = expect.hash
        for _, k in ipairs(keys) do
            local n_fieldtype = hash[k]
            local to_match = only_in_given[k]
            if not to_match then
                -- only in expect
                return false
            end

            only_in_given[k] = nil
            local to_match_type = Types.get_node_type(to_match)
            if not match_type(n_fieldtype, to_match_type) then
                -- not match
                return false
                -- ast_error(to_match, err)
            end
        end
    elseif expect.tag == 'TypeTableProxy' then
        local expect_ast = expect[1]
        for i = 1, #expect_ast, 2 do
            local nk = expect_ast[i]
            local nv = expect_ast[i+1]
            if nk.tag == 'Integer' or nk.tag == 'Id' then
                local k = nk[1]
                local given_ast = only_in_given[k]
                if not given_ast then
                    -- only in expect
                    return false
                end

                only_in_given[k] = nil
                local given_type = Types.get_node_type(given_ast)
                local expect_type = Types.get_node_type(nv)
                if not match_type(expect_type, given_type) then
                    -- not match
                    return false
                end
            end
        end
    else
        ast_error(expect, 'unknown table tag: %s', expect.tag)
        return false
    end

    return not next(only_in_given)
end

match_type = function(expect, given)
    -- 对 any 类型的变量不作检查, any 可以匹配任意类型
    if expect.tag == 'Id' and expect[1] == 'Any' then
        return true
    end
    if given.tag == 'Id' and given[1] == 'Any' then
        return true
    end

    if expect.tag == 'Require' and given.tag == 'Require' then
        if match_type(expect[1], given[1]) then
            return true
        end
    elseif expect.tag == 'Id' and given.tag == 'Id' then
        if is_subtype_of(given[1], expect[1]) then
            return true
        end
    elseif expect.tag == 'VarArg' then
        return true
    elseif expect.tag == 'OptArg' then
        if match_type(expect[1], given) then
            return true
        end
    elseif expect.tag == 'TypeFunction' then
        if given.tag == 'TypeFunction' then
            if match_func_type(expect, given) then
                return true
            end
        end
    elseif expect.tag == 'TypeTableProxy' then
        if given.tag == 'TypeTableProxy' then
            if match_table(expect, given) then
                return true
            end
        end
    elseif expect.tag == 'TypeObj' then
        if given.tag == 'TypeObj' then
            if match_table(expect, given) then
                return true
            end
        elseif given.tag == 'TypeTableProxy' then
            if match_table(expect, given) then
                return true
            end
        end
    elseif expect.tag == 'TypeAlias' then
        if given.tag == 'TypeTableProxy' then
            if match_type(expect[2], given) then
                return true
            end
        end
    end
    return false, sf('expect "%s", but given "%s"', Types.get_full_type_name(expect), Types.get_full_type_name(given))
end

local function match_node_type(node, tp)
    local node_type = Types.get_node_type(node)
    if node_type then
        return match_type(tp, node_type)
    else
        return true
    end
    -- if tp.tag == 'Id' then
    -- elseif tp.tag == 'VarArg' then
    --     return true
    -- elseif tp.tag == 'TypeFunction' then
    --     local node_type = Types.get_node_type(node)
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

local function dump_funcname_aux(b, ast)
    if ast.tag == 'Id' then
        b[#b+1] = ast[1]
    elseif ast.tag == 'IndexShort' then
        assert(ast[2].tag == 'Id')
        dump_funcname_aux(b, ast[1])
        b[#b+1] = '.'
        b[#b+1] = ast[2][1]
    elseif ast.tag == 'Index' then
        dump_funcname_aux(b, ast[1])
        b[#b+1] = '[...]'
    elseif ast.tag == 'Invoke' then
        assert(ast[2].tag == 'Id')
        dump_funcname_aux(b, ast[1])
        b[#b+1] = ':'
        b[#b+1] = ast[2][1]
    end
end

local function dump_funcname(ast)
    local b = {}
    dump_funcname_aux(b, ast)
    b[#b+1] = '()'
    return table.concat(b, '')
end

function F:Call(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_arglist     = ast[2]

    local si = Symbols.find_var(n_funcname)
    if not si then
        walk_node(self, ast)
        return
    end

    local n_parlist
    if si.tag == 'TypeFunction' then
        n_parlist = si[1]
    elseif si.tag == 'OptArg' and si[1].tag == 'TypeFunction' then
        n_parlist = si[1][1]
    elseif si.tag == 'Require' then
        n_parlist = si[1][1]
    elseif si.tag == 'Id' and si[1] == 'Any' then
        -- 调用的函数为 any 类型，跳过检查
        walk_node(self, ast)
        return
    else
        error(sf("expect 'TypeFunction', but given '%s'", si.tag))
    end

    local i_par = 1
    local error_flag = false
    for i_arg = 1, #n_arglist do
        local n_given = n_arglist[i_arg]
        local n_expet = n_parlist[i_par]
        if not n_expet then
            ast_error(ast, "too many arguments to function '%s'", dump_funcname(n_funcname))
            error_flag = true
            break
        end
        local ok, err = match_node_type(n_given, n_expet)
        if not ok then
            ast_error(ast, sf('arg #%d, %s', i_par, err))
            error_flag = true
            break
        end

        if n_expet and n_expet.tag ~= 'VarArg' then
            i_par = i_par + 1
        end
    end

    if not error_flag and i_par <= #n_parlist then
        local n_expet = n_parlist[i_par]
        if n_expet.tag ~= 'VarArg' and n_expet.tag ~= 'OptArg' then
            ast_error(ast, "missing arg #%d (%s) to function '%s'",
                i_par, Types.get_full_type_name(n_expet), dump_funcname(n_funcname))
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
    local si = Symbols.find_var(ast[1])
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
    local si = Symbols.find_var(ast[1])
    if not si then
        ast_error(ast, "close a non-existing table '%s'", dump_typesuffixedname(ast[1]))
    elseif not si.open then
        ast_error(ast, "table '%s' already closed", dump_typesuffixedname(ast[1]))
    else
        si.open = false
    end

    walk_node(self, ast)
end

function F:DumpVar(ast, env, walk_node)
    local si = Symbols.find_var(ast[1])
    print('DumpVar', dump_typesuffixedname(ast[1]))
    print(si and SerializeAst(si))
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
