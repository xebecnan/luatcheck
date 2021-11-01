local Walk = require('walk')
local Types = require('types')
local Symbols = require('symbols')
local Util = require 'util'

local TYPE_NAME2ID = Types.TYPE_NAME2ID
local sf = string.format
local ast_error = Util.ast_error
local dump_table = Util.dump_table

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
    elseif ast.tag == 'Require' then
        return { tag='Require', info=ast.info, convert_type(ast[1]) }
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
    if si.tag == 'Id' and si[1] == 'Any' then
        Symbols.set_var(n_funcname, { tag='Id', 'Any' })
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

function F:FunctionDef(ast, env, walk_node)
    local n_funcname    = ast[1]
    local n_parlist     = ast[2]
    local n_block       = ast[3]

    Symbols.find_var(n_funcname)

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
