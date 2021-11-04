local sf = string.format

local M = {}

function M.to_hash(t)
    local h = {}
    for _, v in ipairs(t) do
        h[v] = true
    end
    return h
end

function M.concat(...)
    local t = {}
    local n = select('#', ...)
    for i = 1, n do
        local tt = select(i, ...)
        for _, v in ipairs(tt) do
            t[#t+1] = v
        end
    end
    return t
end

function M.dump_table(t)
    if type(t) == 'table' then
        local b = {}
        b[#b+1] = '{'
        for k, v in pairs(t) do
            b[#b+1] = sf('%s=%s,', k, v)
        end
        b[#b+1] = '}'
        return table.concat(b, ' ')
    else
        return tostring(t)
    end
end

function M.ast_error(ast, fmt, ...)
    local info = ast and ast.info or {}
    ast.errors = ast.errors or {}
    table.insert(ast.errors, sf('%s:%d: ' .. fmt, info.filename or '?', info.line or 0, ...))
end

return M
