local Parser = require('parser')
local Scoper = require('scoper')
local Binder = require('binder')

local BUILTIN = [[
-->> next :: any, any? >> any
-->> print :: ... >> void
-->> rawset :: any, any, any >> void
-->> require :: handle_require (string >> any)
-->> type :: any >> string
]]

local function init_global_symbols()
    local ast = Parser(BUILTIN, 'BUILTIN')
    Scoper(ast)
    Binder(ast)
    return ast.symbols
end

return function(ast)
    local root = { tag='Block', info=ast.info, symbols=init_global_symbols(), is_root=true, ast }
    ast.is_file = true
    ast.parent = root
    root.scope = root
    return root
end
