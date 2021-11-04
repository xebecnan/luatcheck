local Walk = require('walk')

--------------------------------

local function walk_func(walker, ast, env, walk_node)
    local t = ast.errors
    if t then
        for _, err in ipairs(t) do
            print(err)
        end
    end

    return walk_node(walker, ast)
end

--------------------------------

return function(ast)
    local walker = Walk(walk_func, nil)
    walker(ast)
end
