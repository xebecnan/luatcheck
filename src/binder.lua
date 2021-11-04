local Walk = require('walk')
local Types = require('types')
local Symbols = require('symbols')
local Util = require 'util'
local SerializeAst = require 'serialize_ast'

local TYPE_NAME2ID = Types.TYPE_NAME2ID
local sf = string.format
local ast_error = Util.ast_error
local dump_table = Util.dump_table
local errorf = function(...)
    error(sf(...))
end

local convert_type

local function convert_type_aux(ast)
    if ast.tag == 'TypeFunction' then
        return { tag='TypeFunction', is_require=ast.is_require, convert_type(ast[1]), convert_type(ast[2]) }
    elseif ast.tag == 'Id' then
        local typename = ast[1]

        -- 基础类型
        local id = TYPE_NAME2ID[typename]
        if id then
            return { tag='Id', id }
        end

        -- 自定义类型
        local ti = Symbols.find_type(ast)
        if not ti then
            ast_error(ast, 'unknown type: %s', typename)
        end

        return { tag='TypeAlias', typename, ti }

    elseif ast.tag == 'VarArg' then
        return { tag='VarArg' }
    elseif ast.tag == 'TypeArgList' then
        local nn = { tag='TypeArgList'}
        for i = 1, #ast do
            nn[i] = convert_type(ast[i])
        end
        return nn
    elseif ast.tag == 'TypeObj' then
        local keys = ast.keys
        local hash = ast.hash
        local nn = { tag='TypeObj', keys=keys, hash=hash, open=ast.open }
        for _, k in ipairs(keys) do
            hash[k] = convert_type(hash[k])
        end
        -- for i = 1, #ast, 2 do
        --     nn[i] = ast[i]
        --     nn[i+1] = convert_type(ast[i+1])
        -- end
        return nn
    -- elseif ast.tag == 'CloseTypeObj' then
    --     return { tag='CloseTypeObj' }
    else
        error('unknown type node tag: ' .. ast.tag)
    end
end

convert_type = function(ast)
    local v = convert_type_aux(ast)
    v.info = ast.info
    if ast.is_opt then
        v.is_opt = true
    end
    return v
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

-- 简单的类型推断: 只考虑参数数量，参数和返回值都按 any 类型处理
local function function_def_common(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_parlist     = ast[2]

    local si = Symbols.find_var(n_funcname)
    if si.tag == 'Id' and si[1] == 'Any' then
        Symbols.set_var(n_funcname, Types.inference_func_type(ast.info, n_parlist))
    else
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
            if n_par.tag == 'Id' and not n_type.parname then
                if n_type.tag == 'VarArg' then
                    table.insert(par_types, i, { tag='Id', info=n_type.info, parname=n_par[1], is_opt=true, 'Any' })
                else
                    n_type.parname = n_par[1]
                end
            end
            i = i + 1
        end

        if not error_flag and i <= #par_types then
            local n_type = par_types[i]
            if n_type.tag ~= 'VarArg' then
                ast_error(ast, 'missing arg #%d (%s)', i, Types.get_full_type_name(n_type, true))
            end
        end
    end
end

function F:LocalFunctionDef(ast, env, walk_node)
    function_def_common(ast, env, walk_node)
    walk_node(self, ast)
end

function F:FunctionDef(ast, env, walk_node)
    function_def_common(ast, env, walk_node)
    walk_node(self, ast)
end

function F:Set(ast, env, walk_node)
    -- 没有想清楚，暂时只处理一种情况：往 table 里添加字段
    local name_list = ast[1]
    local expr_list = ast[2]

    for i = 1, #name_list do
        local name = name_list[i]
        local expr = expr_list[i]
        if expr then
            local si = Symbols.find_var(name)
            if not si then
                local expr_type = Types.get_node_type(expr)
                Symbols.set_var(name, expr_type)
            end
        end
    end

    walk_node(self, ast)
end

function F:Local(ast, env, walk_node)
    local n_namelist = ast[1]
    local n_explist = ast[2]
    for  i = 1, #n_namelist do
        local n_name = n_namelist[i]
        local name_type = Symbols.find_var(n_name)
        -- 没有类型信息的话，则为其创建类型信息
        if name_type.tag == 'Id' and name_type[1] == 'Any' then
            local n_exp = n_explist[i]
            if n_exp then
                -- lazy
                local exp_type = { tag='TypeOfExpr', n_exp }
                Symbols.set_var(n_name, exp_type)
            else
                -- 先设置为 any，之后可以进一步细化
                Symbols.set_var(n_name, { tag='Id', 'Any' })
            end
        end
    end

    walk_node(self, ast)
end

function F:Function(ast, env, walk_node)
    Symbols.find_var(ast)

    walk_node(self, ast)
end

function F:Return(ast, env, walk_node)
    local block = ast.scope
    -- 只处理文件层的 return
    if block.tag == 'Block' and block.is_file then
        local mod_type
        if ast[1][1] then
            mod_type = { tag='TypeOfExpr', ast[1][1] }
        else
            mod_type = { tag='Id', 'Any' }
        end
        Symbols.set_var(ast.scope, mod_type)
    end

    walk_node(self, ast)
end

function F:Call(ast, env, walk_node)
    -- 只处理文件层级的
    -- 否则会处理内层的 require()
    -- 出现循环 require 出错
    if ast.scope.is_file then
        local n_funcname = ast[1]
        local si = Symbols.find_var(n_funcname)
        if si and si.tag == 'TypeFunction' and si.is_require then
            if ast[2][1].tag == 'Str' then
                local require_path = ast[2][1][1]
                local requires = ast.scope.requires
                requires[#requires+1] = require_path
                ast.require_path = require_path
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
