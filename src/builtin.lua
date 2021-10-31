local Parser = require('parser')
local Scoper = require('scoper')
local Binder = require('binder')

local BUILTIN = [[
-->> print :: ... >> void
-->> require :: handle_require (string >> any)
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
