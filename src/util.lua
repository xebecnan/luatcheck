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

return M
