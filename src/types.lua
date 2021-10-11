
local sf = string.format
local errorf = function(...)
    error(sf(...))
end

local M = {}

local TYPE_DEF = {
    Any = { name='any' },
    Nil = { name='nil', parent='Any' },
    Void = { name='void', parent='Any' },
    Bool = { name='boolean', parent='Any' },
    Udata = { name='userdata', parent='Any' },
    Number = { name='number', parent='Any' },
    Integer = { name='integer', parent='Number' },
    Float = { name='float', parent='Number' },
    Str = { name='string', parent='Any' },
    Table = { name='table', parent='Any' },
    Never = { name='never', parent='__ALL_TYPES__' },
}

local TYPE_NAME2ID = {}
for id, v in pairs(TYPE_DEF) do
    TYPE_NAME2ID[v.name] = id
end
M.TYPE_NAME2ID = TYPE_NAME2ID

function M.get_type_name(t)
    local v = TYPE_DEF[t] or errorf('unknown type: %s', t)
    return v.name
end

function M.is_bottom_type(t)
    local v = TYPE_DEF[t] or errorf('unknown type: %s', t)
    return v.parent == '__ALL_TYPES__'
end

function M.is_subtype_of(t1, t2)
    if M.is_bottom_type(t1) then
        return true
    end

    local p = t1
    while p do
        if t2 == p then
            return true
        end
        local v = TYPE_DEF[p] or errorf('unknown type: %s', p)
        p = v.parent
    end
    return false
end

function M.is_basetype(t)
    return not not TYPE_DEF[t]
end

return M
