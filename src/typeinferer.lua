-- TODO: 避免往 solution 里添加重复条目

local Util = require 'util'

local dump_table = Util.dump_table
local ast_error = Util.ast_error

local sf = string.format

local function array_append_to(s, d)
    for _, v in ipairs(s) do
        d[#d+1] = v
    end
end

local function table_copy(s, d)
    for k, v in pairs(s) do
        d[k] = v
    end
end

local function array_map_append(s, d, map_func, ...)
    for _, v in ipairs(s) do
        d[#d+1] = map_func(v, ...)
    end
end

local function is_simple_type(v)
    return v.tag == 'SimpleType'
end

local function is_type_var(v)
    return v.tag == 'TypeVar'
end

local function is_func_type(v)
    return v.tag == 'FuncType'
end

local function is_args_type(v)
    return v.tag == 'ArgsType'
end

local is_subtype_of

local simple_type_mt = {
    __tostring = function(v) return sf('%s', v[1]) end,
    __index = nil,
    is_equal_to = function(v1, v2, allow_subtype)
        if v2.tag ~= 'SimpleType' then
            return false
        end

        if v1[1] == v2[1] then
            return true
        end

        if allow_subtype and is_subtype_of(v1, v2) then
            return true
        end

        return false
    end,

    get_parent_type = nil,
}
simple_type_mt.__index = simple_type_mt

local function stype(t)
    return setmetatable(t, simple_type_mt)
end

local t_any         = stype{ tag='SimpleType', 'any' }
local t_nil         = stype{ tag='SimpleType', 'any' }
local t_bool        = stype{ tag='SimpleType', 'bool' }
local t_integer     = stype{ tag='SimpleType', 'integer' }
local t_float       = stype{ tag='SimpleType', 'float' }
local t_number      = stype{ tag='SimpleType', 'number' }
local t_str         = stype{ tag='SimpleType', 'str' }
local t_never       = stype{ tag='SimpleType', 'never' }

local parent_def = {
    [t_nil]     = t_any,
    [t_bool]    = t_any,
    [t_number]  = t_any,
    [t_str]     = t_any,
    [t_integer] = t_number,
    [t_float]   = t_number,
}

simple_type_mt.get_parent_type = function(v)
    return parent_def[v]
end

--local TYPE_DEF = {
--    Any     = { name='any' },
--    Nil     = { parent='Any' },
--    Void    = { parent='Any' },
--    Bool    = { parent='Any' },
--    Udata   = { parent='Any' },
--    Number  = { parent='Any' },
--    Integer = { parent='Number' },
--    Float   = { parent='Number' },
--    Str     = { parent='Any' },
--    Table   = { parent='Any' },
--    Never   = { parent='__ALL_TYPES__' },
--}

local function is_bottom_type(t)
    return t == t_never
end

-- t1 是 t2 的子类型
is_subtype_of = function(t1, t2)
    if is_bottom_type(t1) then
        return true
    end

    local p = t1
    while p do
        if p:is_equal_to(t2) then
            return true
        end
        -- print(p, 'is not equal to', t2)
        p = p:get_parent_type()
        -- local v = TYPE_DEF[p] or error(sf('unknown type: %s', p))
        -- p = v.parent
    end
    return false
end

local function is_type_array_equal(t1, t2, allow_subtype)
    if #t1 ~= #t2 then
        -- print('is_type_array_equal failed. count not match', #t1, #t2)
        return false
    end

    for i = 1, #t1 do
        if not t1[i]:is_equal_to(t2[i], allow_subtype) then
            -- print('is_type_array_equal failed. item not match', i, t1[i], t2[i])
            return false
        end
    end

    return true
end

local function type_array_tostring(t)
    local h = {}
    for _, v in ipairs(t) do
        h[#h+1] = tostring(v)
    end
    return table.concat(h, ',')
end

local args_type_mt = {
    __tostring = function(v) return sf('[%s]', type_array_tostring(v.arg_types)) end,
    __index = nil,
    is_equal_to = function(v1, v2, allow_subtype)
        if v2.tag ~= 'ArgsType' then
            -- print('ArgsType eq failed: v2.tag:', v2.tag)
            return false
        end

        return is_type_array_equal(v1.arg_types, v2.arg_types, allow_subtype)
    end,
    get_parent_type = function(v)
        return t_any
    end,
}
args_type_mt.__index = args_type_mt

local function create_args_type(arg_types)
    return setmetatable({tag='ArgsType', arg_types=arg_types}, args_type_mt)
end

local func_type_mt = {
    __tostring = function(v) return sf('{%s -> %s}', v.args, v.rets) end,
    __index = nil,
    is_equal_to = function(v1, v2, allow_subtype)
        if v2.tag ~= 'FuncType' then
            return false
        end

        return v1.args:is_equal_to(v2.args, allow_subtype)
           and v1.rets:is_equal_to(v2.rets, allow_subtype)
    end,
}
func_type_mt.__index = func_type_mt

local function create_func_type(args, rets)
    assert(args.tag == 'ArgsType' or is_type_var(args))
    assert(rets.tag == 'ArgsType' or is_type_var(rets))
    return setmetatable({tag='FuncType', args=args, rets=rets}, func_type_mt)
end

--local function is_type_equal(t1, t2)
--    if t1.tag ~= t2.tag then
--        return false
--    end
--
--    if is_simple_type(t1) then
--        return t1[1] == t2[1]
--    end
--
--    if is_type_var(t1) then
--        return t1:is_equal_to(t2)
--    end
--
--    error(sf('not supported type: %s', t1.tag))
--end

----------------------------------------------------------------

local type_var_mt = {
    __tostring = function(v)
        if v.st == t_any then
            return sf('t%s', v.type_id)
        else
            return sf('t%s(%s)', v.type_id, v.st)
        end
    end,
    __index = nil,

    is_equal_to = function(v1, v2, allow_subtype)
        if v2.tag ~= 'TypeVar' then
            return false
        end

        return v1.type_id and v1.type_id == v2.type_id or false
    end,

    narrow = function(v, target_type)
        if target_type:is_equal_to(v.st) then
            return true
        end
        if is_subtype_of(target_type, v.st) then
            v.st = target_type
            return true
        end
        print('!!!!!!!!!!!! narrow failed !!!!!!!!!!!!', target_type, v.st)
        return false
    end,
}

type_var_mt.__index = type_var_mt

local latest_id = 0

local function create_type_variable()
    latest_id = latest_id + 1
    return setmetatable(
        -- st: supposed type
        { tag='TypeVar', type_id=latest_id, st=t_any },
        type_var_mt
        )
end

----------------------------------------------------------------

local function add_solution(ss, type_var, t)
    -- if is_args_type(t) and #t.arg_types == 1 then
    --     t = t.arg_types[1]
    -- end

    assert(is_type_var(type_var))
    ss[#ss+1] = { type_var, t }  -- type_var -> t
    print(sf('    (S) %s => %s', type_var, t))
end

local function unification_step(v, h, s, ss)
    -- t1: given
    -- t2: require
    local t1, t2 = v[1], v[2]
    if t1:is_equal_to(t2, true) then
        -- do nothing
        print('SKIP:', t1, t2)
        return nil
    else
        print(sf('"%s" is not equal or subtype to "%s"', t1, t2))
    end

    --if is_subtype_of(t1, t2) then
    --    print('SKIP:', t1, t2)
    --    return nil
    --end

    if is_simple_type(t1) and is_type_var(t2) then
        -- s[#s+1] = { t2, t1 }
        -- ss[#ss+1] = { t2, t1 }  -- t2 -> t1
        add_solution(ss, t2, t1)
        return nil
    end

    if is_type_var(t1) and is_simple_type(t2) then
        -- s[#s+1] = { t1, t2 }
        -- ss[#ss+1] = { t1, t2 }  -- t1 -> t2
        add_solution(ss, t1, t2)
        return nil
    end

    if is_args_type(t1) and is_type_var(t2) then
        add_solution(ss, t2, t1)
        return nil
    end

    if is_type_var(t1) and is_args_type(t2) then
        add_solution(ss, t1, t2)
        return nil
    end

    if is_func_type(t1) and is_func_type(t2) then
        h[#h+1] = { t1.args, t2.args }
        h[#h+1] = { t1.rets, t2.rets }
        print(sf('  [C] %s == %s', t1.args, t2.args))
        print(sf('  [C] %s == %s', t1.rets, t2.rets))
        return nil
    end

    if is_args_type(t1) and is_args_type(t2) then
        local n = math.max(#t1.arg_types, #t2.arg_types)
        for i = 1, n do
            h[#h+1] = { t1.arg_types[i] or t_any, t2.arg_types[i] or t_any }
            print(sf('  [C] %s == %s', t1.arg_types[i], t2.arg_types[i]))
        end
        return nil
    end

    print('## ERROR ####################################')
    print(t1)
    print(t2)
    return true
end

local function substitute_aux(v, sub)
    local fr, to = sub[1], sub[2]
    -- print('substitute_aux', v, '|', fr, to)
    assert(is_type_var(fr))

    if is_func_type(v) then
        return create_func_type(substitute_aux(v.args, sub), substitute_aux(v.rets, sub))
    end

    if is_args_type(v) then
        local h = {}
        array_map_append(v.arg_types, h, substitute_aux, sub)
        return create_args_type(h)
    end

    -- FIXME: 要不要用 type equal 来判断相等?
    if v == fr then
        -- print('NARROW', v, to)
        v:narrow(to)
        return v
    else
        return v
    end
end

local function do_subtitution(h, sub)
    for _, v in ipairs(h) do
        v[1] = substitute_aux(v[1], sub)
        v[2] = substitute_aux(v[2], sub)
    end
end

local function do_unificaion(c, s)
    local unification_error = false
    local h = {}
    array_append_to(c, h)

    print('-- start unification ------------------------')
    local ss = {}
    while #h > 0 do
        local v = table.remove(h, 1)
        local err = unification_step(v, h, s, ss)
        for i = #ss, 1, -1 do
            local sub = ss[i]
            ss[i] = nil
            do_subtitution(h, sub)
            s[#s+1] = sub
        end
        if err then
            unification_error = true
        end
    end
    print('=============================================')
    print('== solution                                ==')
    for _, v in ipairs(s) do
        print(v[1], '==', v[2])
    end
    print('-- end unification --------------------------')
    return unification_error
end

local F = {}

local function inferer_func(ast, env, C)
    local f = F[ast.tag] or error(sf('unknown tag: %s', ast.tag))
    return f(ast, env, C)
end

function F.Id(ast, env, C)
    local t = env[ast[1]]
    assert(t)
    print('Id', ast[1], 'type:', t)
    return t
end

function F.Block(ast, env, C)
    return inferer_func(ast[1], env, C)
end

function F.Return(ast, env, C)
    -- -- TODO: 返回多个值的情况
    -- print('Return', ast[1] and dump_table(ast[1]))
    -- 因为可能有多个返回值，所以 ast[1] 是一个 ExpList
    return inferer_func(ast[1], env, C)
end

function F.ExpList(ast, env, C)
    local h = {}
    local err = false
    for i = 1, #ast do
        local t = inferer_func(ast[i], env, C)
        if t then
            h[#h+1] = t
        else
            err = true
        end
    end
    if err then
        return nil
    end

    return create_args_type(h)
end

function F.Nil(ast, env, C)
    return t_nil
end

function F.Bool(ast, env, C)
    return t_bool
end

function F.Integer(ast, env, C)
    return t_integer
end

function F.Float(ast, env, C)
    return t_float
end

function F.Str(ast, env, C)
    return t_str
end

local function resolve(t, c)
    local s = {}
    local err = do_unificaion(c, s)
    if err then
        return nil, 'type error'
    end
    for _, sub in ipairs(s) do
        t = substitute_aux(t, sub)
        if is_simple_type(t) then
            break
        end
    end
    return t
end

function F.If(ast, env, C)
    -- 创建一个未知类型 作为 if 语句的返回类型
    local t = create_type_variable()
    print('IF:', t)
    for i = 1, #ast, 2 do
        -- 约束: 条件的类型必须为 any
        local cond_type = inferer_func(ast[i], env, C)
        C[#C+1] = { cond_type, t_any }
        print(sf('  [C] %s == %s', cond_type, t_any))

        -- 约束: 分支的类型必须与 t 相同
        local body_type = inferer_func(ast[i+1], env, C)
        C[#C+1] = { body_type, t }
        print(sf('  [C] %s == %s', t, body_type))
    end

    -- local tt, err = resolve(t, c)
    -- if not tt then
    --     ast_error(ast, err)
    -- end
    -- print('*********************************************')
    -- print('Resolve of IF:', tt)
    -- return tt
    return t

    -- local s = {}
    -- local err = do_unificaion(c, s)
    -- if err then
    --     ast_error(ast, 'type error')
    -- end
    -- for _, sub in ipairs(s) do
    --     t = substitute_aux(t, sub)
    --     if is_simple_type(t) then
    --         break
    --     end
    -- end
    -- print('*********************************************')
    -- print('Resolve of IF:', dump_table(t))
    -- return t
end

local number_binopr_map = {
    ['+'] = true,
    ['-'] = true,
    ['*'] = true,
    ['/'] = true,
    ['//'] = true,
    ['%'] = true,
    ['^'] = true,
}

local string_binopr_map = {
    ['..'] = true,
}

function F.BinOpr(ast, env, C)
    local op, n1, n2 = ast[1], ast[2], ast[3]

    local t = create_type_variable()
    print(sf('BinOpr %s: %s', op, t))

    local t1 = inferer_func(n1, env, C)
    local t2 = inferer_func(n2, env, C)

    local args1 = create_args_type{ t1, t2 }
    local rets1 = create_args_type{ t }
    local func1 = create_func_type(args1, rets1)

    local func2 = env[op] or error(sf('cannot find type for op: %s', op))

    -- application (+) t1 t2
    -- C: (type of '+') == (args(t1 t2) -> args(t))
    C[#C+1] = { func1, func2 }
    print(sf('  [C] %s == %s', func1, func2))

    -- local tt, err = resolve(t, c)
    -- if not tt then
    --     ast_error(ast, err)
    -- end
    -- print('*********************************************')
    -- print(sf('Resolve of BinOpr(%s): %s', op, tt))
    -- return tt
    return t

    -- if number_binopr_map[op] then
    --     local t = create_type_variable()

    --     local c = {}
    --     local t1 = inferer_func(n1, env, c)
    --     c[#c+1] = { t1, t_number }

    --     local t2 = inferer_func(n2, env, c)
    --     c[#c+1] = { t2, t_number }

    --     -- c[#c+1] = { (number, number >> number) = (t1, t2 >> t) }
    --     local args1 = create_args_type{ t1, t2 }
    --     local rets1 = create_args_type{ t }
    --     local func1 = create_func_type(args1, rets1)

    --     local func2 = env[op] or error(sf('cannot find type for op: %s', op))

    --     c[#c+1] = { func1, func2 }

    --     local tt, err = resolve(t, c)
    --     if not tt then
    --         ast_error(ast, err)
    --     end
    --     print('*********************************************')
    --     print('Resolve of BinOpr(+):', tt)
    --     return tt
    -- end

    -- if op == '..' then
    --     local t = create_type_variable()

    --     local c = {}
    --     local t1 = inferer_func(n1, env, c)
    --     c[#c+1] = { t1, t_str }

    --     local t2 = inferer_func(n2, env, c)
    --     c[#c+1] = { t2, t_str }

    --     -- c[#c+1] = { (number, number >> number) = (t1, t2 >> t) }
    --     local args1 = create_args_type{ t1, t2 }
    --     local rets1 = create_args_type{ t }
    --     local func1 = create_func_type(args1, rets1)

    --     local args2 = create_args_type{ t_str, t_str }
    --     local rets2 = create_args_type{ t_str }
    --     local func2 = create_func_type(args2, rets2)

    --     c[#c+1] = { func1, func2 }

    --     local tt, err = resolve(t, c)
    --     if not tt then
    --         ast_error(ast, err)
    --     end
    --     print('*********************************************')
    --     print('Resolve of BinOpr(..):', tt)
    --     return tt
    -- end

    -- print('!! BinOpr !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!')
    -- print(dump_table(ast))
end

function F.Function(ast, env, C)
    local n_parlist = ast[1]
    local n_block = ast[2]

    local new_env = {}
    table_copy(env, new_env)

    local h = {}
    for i = 1, #n_parlist do
        local v = n_parlist[i]
        if v.tag == 'Id' then
            local t = create_type_variable()
            h[#h+1] = t
            new_env[v[1]] = t
            print(sf('Function arg %s: %s', v[1], t))
        elseif v.tag == 'VarArg' then
            -- TODO
        else
            print('~~~~', i, dump_table(v))
        end
    end

    local c = {}
    local args = create_args_type(h)
    -- local rets = create_args_type{ inferer_func(n_block, new_env, c) }
    local rets = inferer_func(n_block, new_env, c)
    array_append_to(c, C)

    local t = create_func_type(args, rets)

    -- local tt, err = resolve(t, c)
    -- if not tt then
    --     ast_error(ast, err)
    -- end
    -- print('*********************************************')
    -- print('Resolve of Function:', tt)
    -- return tt
    return t
end

local function reg_number_binopr(env)
    local args = create_args_type{ t_number, t_number }
    local rets = create_args_type{ t_number }
    local func = create_func_type(args, rets)
    for op in pairs(number_binopr_map) do
        env[op] = func
    end
end

local function reg_string_binopr(env)
    local args = create_args_type{ t_str, t_str }
    local rets = create_args_type{ t_str }
    local func = create_func_type(args, rets)
    for op in pairs(string_binopr_map) do
        env[op] = func
    end
end

local function reg_buildtin(env)
    reg_number_binopr(env)
    reg_string_binopr(env)
end

-- return function(ast)
--     return inferer
-- end
return function(ast)
    local env = {}

    reg_buildtin(env)

    local c = {}
    local t = inferer_func(ast, env, c)
    local tt, err = resolve(t, c)
    if not tt then
        ast_error(ast, err)
    end
    print('*********************************************')
    print('|| typeinferer resolve ||:', tt)
    return tt
end
