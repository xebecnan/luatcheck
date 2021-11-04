local require_cache = {}
local dummy = {}

return function(require_path)
    local require_info = require_cache[require_path]
    if not require_info then
        require_cache[require_path] = dummy

        local require_type
        local requires
        local filename = require_path:gsub('%.', '\\') .. '.lua'
        local f = io.open(filename, 'r')
        if f then
            local c = f:read('a')
            f:close()

            local Parser = require('parser')
            local Scoper = require('scoper')
            local Builtin = require('builtin')
            local Binder = require('binder')
            local Symbols = require('symbols')

            local ast = Parser(c, filename, true)
            if ast then
                Scoper(ast)
                local root = Builtin(ast)
                Binder(root)
                local file_block = root[1]
                assert(file_block.is_file == true)
                require_type = Symbols.find_var(file_block)
                requires = ast.requires
            end
        end
        require_type = require_type or { tag='Id', 'Any' }
        require_info = {
            require_type = require_type,
            requires = requires,
        }
        require_cache[require_path] = require_info
    end
    return require_info
end

