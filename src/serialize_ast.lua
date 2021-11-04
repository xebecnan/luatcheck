-- luacheck: ignore 213

local oprint = print
local print = print
local dummy = function() end

local sf = string.format

local dump_table
local INDENT_STR = "  "

local function dump_indent(indent, buffer, n)
    for i=1,indent do
        n=n+1; buffer[n] = INDENT_STR
    end
    return n
end

local function dump_field(k, v, hist, indent, buffer, n)
    local tpk, tpv = type(k), type(v)
    local kk
    if tpk == "string" then
        kk = sf("%q", k)
    else
        kk = tostring(k)
    end
    if tpv == "table" then
        n = dump_indent(indent, buffer, n)
        n=n+1; buffer[n] = "["
        if tpk == 'table' then
            n = dump_table(k, hist, indent, buffer, n)
        else
            n=n+1; buffer[n] = kk
        end
        n=n+1; buffer[n] = "]="

        -- recursive
        n = dump_table(v, hist, indent, buffer, n)

        n=n+1; buffer[n] = ",\n"
    else
        if tpv == "string" then
            v = sf("%q", v)
        else
            v = tostring(v)
        end
        n = dump_indent(indent, buffer, n)
        n=n+1; buffer[n] = "["
        n=n+1; buffer[n] = kk
        n=n+1; buffer[n] = "]="
        n=n+1; buffer[n] = v
        n=n+1; buffer[n] = ",\n"
    end

    return n
end

local function dump_ordered_field(v, hist, indent, buffer, n)
    local tpv = type(v)
    if tpv == "table" then
        n = dump_indent(indent, buffer, n)

        -- recursive
        n = dump_table(v, hist, indent, buffer, n)

        n=n+1; buffer[n] = ",\n"
    else
        if tpv == "string" then
            v = sf("%q", v)
        else
            v = tostring(v)
        end
        n = dump_indent(indent, buffer, n)
        n=n+1; buffer[n] = v
        n=n+1; buffer[n] = ",\n"
    end

    return n
end

dump_table = function(t, hist, indent, buffer, n)
    if hist[t] then
        error('recursive table found!')
    end
    hist[t] = true

    indent = indent or 0

    local hide_info
    local hide_tag

    local is_ast = type(t.tag) == 'string'

    -- 对 tag 和 info 用特殊格式进行显示
    if is_ast and t.tag then
        n=n+1; buffer[n] = "$"
        n=n+1; buffer[n] = t.tag
        hide_tag = true

        if t.info then
            -- if not t.info.line then
            --     n=n+1; buffer[n] = 'ERROR t.info {'
            --     for k, v in pairs(t.info) do
            --         n=n+1; buffer[n] = sf('k:%s, v:%s, ', k, v)
            --     end
            --     n=n+1; buffer[n] = '}'
            --     n=n+1; buffer[n] = 'ERROR t {'
            --     for k, v in pairs(t) do
            --         n=n+1; buffer[n] = sf('k:%s, v:%s, ', k, v)
            --     end
            --     n=n+1; buffer[n] = '}'
            -- end
            n=n+1; buffer[n] = sf(' (%s:%d) ', t.info.filename, t.info.line)
            hide_info = true
        end
    end

    n=n+1; buffer[n] = "{\n"
    indent = indent + 1

    local skeys = {}
    local nkeys = {}
    local okeys = {}
    local size = #t

    for k in pairs(t) do
        if type(k) == 'string' then
            if not is_ast
                or ( not (k == 'tag' and hide_tag)
                    and not (k == 'info' and hide_info)
                    and k ~= 'scope'
                    and k ~= 'parent'
                    and k ~= 'errors'
                )
            then
                skeys[#skeys+1] = k
            end
        elseif type(k) == 'number' and math.type(k) == 'integer' and k <= size then
            nkeys[#nkeys+1] = k
        else
            okeys[#okeys+1] = k
        end
    end
    table.sort(skeys)
    table.sort(nkeys)

    print('<<<<<<<<<<<<<<<<<<<<<<<<')
    for i = 1, #skeys do
        local k = skeys[i]
        local v = t[k]
        print('skey', k)
        n = dump_field(k, v, hist, indent, buffer, n)
    end
    for i = 1, #okeys do
        local k = okeys[i]
        local v = t[k]
        print('okey', k)
        n = dump_field(k, v, hist, indent, buffer, n)
    end
    local next_nk = 1
    for i = 1, #nkeys do
        local k = nkeys[i]
        local v = t[k]
        while next_nk < k do
            n = dump_ordered_field(nil, hist, indent, buffer, n)
            next_nk = next_nk + 1
        end
        print('nkey', k)
        n = dump_ordered_field(v, hist, indent, buffer, n)
        next_nk = k + 1
    end
    print('>>>>>>>>>>>>>>>>>>>>>>>>')

    indent = indent - 1

    n = dump_indent(indent, buffer, n)
    n=n+1; buffer[n] = "}"

    hist[t] = nil

    return n
end

-->> $ :: any, boolean? >> string
return function(t, debug)
    local buffer = {}
    local hist = {}

    print = debug and oprint or dummy

    dump_table(t, hist, 0, buffer, 0)

    local nb = {}
    for i, v in ipairs(buffer) do
        if type(v) == 'string' then
            nb[i] = v
        else
            nb[i] = sf('ERRORTYPE %s', type(v))
        end
    end
    buffer = nb
    return table.concat(buffer, '')
end

