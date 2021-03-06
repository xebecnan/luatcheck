local require_cache = {}
local dummy = {}
local SEP = package.config:sub(1,1)

return function(require_path)
    local require_info = require_cache[require_path]
    if not require_info then
        require_cache[require_path] = dummy

        local require_type
        local requires
        local require_err
        local filename = require_path:gsub('%.', SEP) .. '.lua'
        local f = io.open(filename, 'r')
        if f then
            local c = f:read('a')
            f:close()

            local Parser = require('parser')
            local Scoper = require('scoper')
            local Builtin = require('builtin')
            local Binder = require('binder')
            local Symbols = require('symbols')

            local ast, err = Parser(c, filename, true)
            if ast then
                Scoper(ast)
                local root = Builtin(ast)
                Binder(root)
                local file_block = root[1]
                assert(file_block.is_file == true)
                require_type = Symbols.find_var(file_block)
                requires = ast.requires
            else
                require_err = err
            end
        end
        require_type = require_type or { tag='Id', 'Any' }
        require_info = {
            require_type = require_type,
            requires = requires,
            require_err = require_err
        }
        require_cache[require_path] = require_info
    end
    return require_info
end

