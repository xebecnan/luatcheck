-- luacheck: ignore 212

local sf = string.format

local F = {}

local function walk(walker, ast)
    local f = F[ast.tag] or error(sf('unknown tag: %s', ast.tag))

    return walker.walk_func(walker, ast, walker.udata, f)
end

function F:BinOpr(ast)
    walk(self, ast[2])
    walk(self, ast[3])
end

function F:Block(ast)
    for i = 1, #ast do
        walk(self, ast[i])
    end
end

function F:Bool(ast)
    -- pass
end

function F:Break(ast)
    -- pass
end

function F:Call(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:Do(ast)
    walk(self, ast[1])  -- block
end

function F:EmptyStat(ast)
    -- pass
end

function F:ExpList(ast)
    for i = 1, #ast do
        walk(self, ast[i])
    end
end

function F:Float(ast)
    -- pass
end

function F:Forin(ast)
    walk(self, ast[1])
    walk(self, ast[2])
    walk(self, ast[3])
end

function F:Fornum(ast)
    walk(self, ast[1])  -- n_var1
    walk(self, ast[2])  -- n1
    walk(self, ast[3])  -- n2
    if ast[4] then
        walk(self, ast[4])  -- n3
    end
    walk(self, ast[5])  -- n_block
end

function F:FuncName(ast)
    for i = 1, #ast do
        walk(self, ast[i])
    end
end

function F:Function(ast)
    walk(self, ast[1])  -- n_parlist
    walk(self, ast[2])  -- n_block
end

function F:FunctionDef(ast)
    walk(self, ast[1])
    walk(self, ast[2])
    walk(self, ast[3])
end

function F:Goto(ast)
    walk(self, ast[1])
end

function F:Id(ast)
    -- pass
end

function F:If(ast)
    for i = 1, #ast, 2 do
        walk(self, ast[i])
        walk(self, ast[i+1])
    end
end

function F:Index(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:IndexShort(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:Integer(ast)
    -- pass
end

function F:Invoke(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:Label(ast)
    walk(self, ast[1])
end

function F:Local(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:LocalFunctionDef(ast)
    walk(self, ast[1])
    walk(self, ast[2])
    walk(self, ast[3])
end

function F:NameList(ast)
    for i = 1, #ast do
        walk(self, ast[i])
    end
end

function F:Nil(ast)
    -- pass
end

function F:Repeat(ast)
    walk(self, ast[1])  -- block
    walk(self, ast[2])  -- cond
end

function F:Return(ast)
    walk(self, ast[1])
end

function F:Set(ast)
    walk(self, ast[1])  -- block
    walk(self, ast[2])  -- cond
end

function F:Str(ast)
    -- pass
end

function F:Table(ast)
    for i = 1, #ast, 2 do
        walk(self, ast[i])
        walk(self, ast[i+1])
    end
end

function F:Tpblock(ast)
    for i = 1, #ast do
        walk(self, ast[i])
    end
end

function F:Tpdef(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:Tpbind(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:TypeArgList(ast)
    for i = 1, #ast do
        walk(self, ast[i])
    end
end

function F:TypeFunction(ast)
    walk(self, ast[1])
    walk(self, ast[2])
end

function F:TypeObj(ast)
    local keys = ast.keys
    local hash = ast.hash
    for _, k in ipairs(keys) do
        walk(self, hash[k])
    end
end

function F:OpenTypeObj(ast)
    walk(self, ast[1])
end

function F:CloseTypeObj(ast)
    walk(self, ast[1])
end

function F:UnOpr(ast)
    walk(self, ast[2])
end

function F:VarArg(ast)
    -- pass
end

function F:While(ast)
    walk(self, ast[1])  -- cond
    walk(self, ast[2])  -- block
end

function F:OptArg(ast)
    walk(self, ast[1])
end

function F:DumpVar(ast)
    walk(self, ast[1])
end

function F:Require(ast)
    walk(self, ast[1])
end

function F:RefToNextSymbol(ast)
    -- pass
end

return function(walk_func, udata)
    return setmetatable({
        walk_func = walk_func,
        udata = udata,
    }, {
        __index = F,
        __call = function(self, ast)
            return walk(self, ast)
        end,
    })
end
