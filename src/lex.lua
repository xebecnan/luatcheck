local Util = require 'util'
local to_hash = Util.to_hash
local concat = Util.concat

local SPACE = { ' ', '\f', '\t', '\v' }
local EOL = { '\r', '\n' }
local ALPHA = {
    'a', 'b', 'c', 'd', 'e', 'f', 'g',
    'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't',
    'u', 'v', 'w', 'x', 'y', 'z',
    'A', 'B', 'C', 'D', 'E', 'F', 'G',
    'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
}
local DIGIT = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', }
local XDIGIT = {
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'a', 'b', 'c', 'd', 'e', 'f',
    'A', 'B', 'C', 'D', 'E', 'F',
}
local UNDERSCORE = { '_' }
local RESERVED = {
    'local', 'nil', 'end', 'until', 'return', 'function', 'not',
    'if', 'then', 'elseif', 'else',
    'while', 'do', 'for', 'repeat', 'break', 'goto', 'in',
    'true', 'false',
    'and', 'or',
}
local SIMPLE_ESCAPE = { a='\a', b='\b', f='\f', n='\n', r='\r', t='\t', v='\v', }

local IS_SPACE = to_hash(SPACE)
local IS_EOL = to_hash(EOL)
local IS_ALHPA = to_hash(ALPHA)
local IS_DIGIT = to_hash(DIGIT)
local IS_XDIGIT = to_hash(XDIGIT)
-- local IS_ALNUM = to_hash(concat(ALPHA, DIGIT))
local IS_LALNUM = to_hash(concat(ALPHA, DIGIT, UNDERSCORE))
local IS_RESERVED = to_hash(RESERVED)

return function(s, debug_hint, is_file)
    local c
    local i = 1
    local line_no = 1

    local function lex_error(msg)
        error(msg .. '\n' .. debug_hint)
    end

    local function readhexaesc()
        local b = {}

        i = i + 1; c = s:sub(i, i)
        if not IS_XDIGIT[c] then
            lex_error('hexadecimal digit expected')
        end
        b[#b+1] = c

        i = i + 1; c = s:sub(i, i)
        if not IS_XDIGIT[c] then
            lex_error('hexadecimal digit expected')
        end
        b[#b+1] = c

        return string.char(tonumber(table.concat(b, ''), 16))
    end

    local function readdecesc()
        local v = 0
        for _ = 1, 3 do
            if not IS_DIGIT[c] then
                break
            end
            v = v * 10 + (string.byte(c) - string.byte('0'))
            i = i + 1; c = s:sub(i, i)
        end
        i = i - 1
        return string.char(v)
    end

    local function readstring()
        local del = c
        local b = {}
        while true do
            i = i + 1; c = s:sub(i, i)
            if c == del then
                i = i + 1; c = s:sub(i, i)
                break
            end

            if not c then
                lex_error('unfinished string near <eof>')
            elseif IS_EOL[c] then
                lex_error('unfinished string near <string>')
            elseif c == '\\' then  -- escape sequences
                i = i + 1; c = s:sub(i, i)
                local cc = SIMPLE_ESCAPE[c]
                if cc then
                    b[#b+1] = cc
                elseif c == 'x' then
                    b[#b+1] = readhexaesc()
                elseif c == 'u' then
                    lex_error('TODO')
                elseif IS_EOL[c] then
                    b[#b+1] = '\n'
                    line_no = line_no + 1
                elseif c == '\\' or c =='"' or c == "'" then
                    b[#b+1] = c
                elseif c == nil then
                    lex_error('unfinished string near <eof>')
                elseif c == 'z' then
                    lex_error('TODO')
                elseif IS_DIGIT[c] then
                    b[#b+1] = readdecesc()
                else
                    lex_error('invalid escape sequence')
                end
            else
                b[#b+1] = c
            end
        end
        return table.concat(b, '')
    end

    local function read_numeral()
        local is_hex = false
        local b = {}
        if c == '0' then
            b[#b+1] = c
            i = i + 1; c = s:sub(i, i)
            if c == 'x' or c == 'X' then
                b[#b+1] = c; i = i + 1; c = s:sub(i, i)
                is_hex = true
            end
        end

        while true do
            local is_exp_mark
            if is_hex then
                is_exp_mark = (c == 'p' or c == 'P')
            else
                is_exp_mark = (c == 'e' or c == 'E')
            end

            if is_exp_mark then
                b[#b+1] = c; i = i + 1; c = s:sub(i, i)
                if c == '-' or c == '+' then
                    b[#b+1] = c; i = i + 1; c = s:sub(i, i)
                end
            elseif IS_XDIGIT[c] or c == '.' then
                b[#b+1] = c; i = i + 1; c = s:sub(i, i)
            else
                break
            end
        end

        -- force an error
        if IS_ALHPA[c] then
            b[#b+1] = c; i = i + 1; c = s:sub(i, i)
        end

        local v = tonumber(table.concat(b, ''))
        local t = math.type(v)
        if t == 'integer' then
            return 'INT', v
        elseif t == 'float' then
            return 'FLT', v
        else
            lex_error('malformed number')
        end
    end

    local function skip_sep()
        local b = { c }
        local cc = c
        i = i + 1; c = s:sub(i, i)  -- skip '[' or ']'
        local count = 0
        while c == '=' do
            b[#b+1] = c
            i = i + 1; c = s:sub(i, i)
            count = count + 1
        end
        local bb = table.concat(b, '')
        if c == cc then
            return count + 2, bb
        elseif count == 0 then
            return 1, bb
        else
            return 0, bb
        end
    end

    local function read_long_string(sep)
        local b = {}
        while true do
            if c == '' then
                lex_error('unfinished long string')
                break
            elseif c == ']' then
                local ssep, bb = skip_sep()
                if ssep == sep then
                    i = i + 1; c = s:sub(i, i)  -- skip ']'
                    break
                else
                    b[#b+1] = bb
                end
            elseif IS_EOL[c] then
                b[#b+1] = c
                i = i + 1; c = s:sub(i, i)
                line_no = line_no + 1
            else
                b[#b+1] = c
                i = i + 1; c = s:sub(i, i)
            end
        end
        return table.concat(b, '')
    end

    local function skip_short_comment()
        while not IS_EOL[c] and c ~= '' do
            i = i + 1; c = s:sub(i, i)
        end
    end

    local function skip_long_comment()
        local sep = skip_sep()
        i = i + 1; c = s:sub(i, i)
        if sep >= 2 then
            read_long_string(sep)
        else
            skip_short_comment()
        end
    end

    local function try_read_tpdef_begin()
        local saved = i
        i = i + 1; c = s:sub(i, i)
        if c == '[' then
            i = i + 1; c = s:sub(i, i)
            if c == '>' then
                i = i + 1; c = s:sub(i, i)
                if c == '>' then
                    i = i + 1
                    return true
                end
            end
        end
        i = saved; c =s:sub(i, i)
        return false
    end

    local function try_read_tpdef_end()
        local saved = i
        i = i + 1; c = s:sub(i, i)
        if c == ']' then
            i = i + 1; c = s:sub(i, i)
            if c == ']' then
                i = i + 1
                return true
            end
        end
        i = saved; c = s:sub(i, i)
        return false
    end

    -- skip first line comment: #!/usr/bin/env lua
    if is_file then
        c = s:sub(i, i)
        if c == '#' then
            while true do
                i = i + 1; c = s:sub(i, i)
                if c == '' then
                    break
                elseif IS_EOL[c] then
                    line_no = line_no + 1
                    i = i + 1
                    break
                end
            end
        end
    end

    return function(p)
        if p == 'LINE_NO' then
            return line_no
        end

        ::continue::

        c = s:sub(i, i)
        if c == '' then
            return 'EOS', nil
        end
        -- print(i, c)

        if IS_EOL[c] then
            line_no = line_no + 1
            i = i + 1; goto continue
        end

        if IS_SPACE[c] then
            i = i + 1; goto continue
        end

        if c == '-' then
            i = i + 1; c = s:sub(i, i)
            if c ~= '-' then
                return '-', nil
            end
            i = i + 1; c = s:sub(i, i)
            if c == '[' then
                if try_read_tpdef_begin() then
                    return 'TPDEF_BEGIN', nil
                end
                skip_long_comment()
                goto continue
            end
            if c == '>' then
                i = i + 1; c = s:sub(i, i)
                if c == '>' then
                    i = i + 1
                    return 'TPLINE', nil
                end
                i = i - 1; c = s:sub(i, i)
            end
            skip_short_comment()
            goto continue
        end

        if c == '[' then
            local sep = skip_sep()
            if sep >= 2 then
                return 'STR', read_long_string(sep)
            elseif sep == 0 then
                lex_error('invalid long string delimiter')
            else
                return '['
            end
        end

        if c == '=' then
            i = i + 1; c = s:sub(i, i)
            if c == '=' then
                i = i + 1
                return '==', nil
            else
                return '=', nil
            end
        end

        if c == '<' then
            i = i + 1; c = s:sub(i, i)
            if c == '=' then
                i = i + 1
                return '<=', nil
            elseif c == '<' then
                if try_read_tpdef_end() then
                    return 'TPDEF_END', nil
                end
                i = i + 1
                return '<<', nil
            else
                return '<'
            end
        end

        if c == '>' then
            i = i + 1; c = s:sub(i, i)
            if c == '=' then
                i = i + 1
                return '>=', nil
            elseif c == '>' then
                i = i + 1
                return '>>', nil
            else
                return '>'
            end
        end

        if c == '/' then
            i = i + 1; c = s:sub(i, i)
            if c == '/' then
                i = i + 1
                return '//', nil
            else
                return '/', nil
            end
        end

        if c == '~' then
            i = i + 1; c = s:sub(i, i)
            if c == '=' then
                i = i + 1
                return '~=', nil
            else
                return '~', nil
            end
        end

        if c == ':' then
            i = i + 1; c = s:sub(i, i)
            if c == ':' then
                i = i + 1
                return '::', nil
            else
                return ':', nil
            end
        end

        -- short literal strings
        if c == '"' or c == "'" then
            return 'STR', readstring()
        end

        -- '.', '..', '...', or number
        if c == '.' then
            i = i + 1; c = s:sub(i, i)
            if c == '.' then
                i = i + 1; c = s:sub(i, i)
                if c == '.' then
                    i = i + 1
                    return '...', nil
                else
                    return '..', nil
                end
            elseif not IS_DIGIT[c] then
                return '.'
            else
                return read_numeral()
            end
        end

        if IS_DIGIT[c] then
            return read_numeral()
        end

        if IS_LALNUM[c] then
            local b = {}
            repeat
                b[#b+1] = c
                i = i + 1
                c = s:sub(i, i)
                -- print('i:', i, 'c:', c, 'isalnum:', IS_ALNUM[c])
            until not IS_LALNUM[c]

            local v = table.concat(b, '')
            if IS_RESERVED[v] then
                return v, nil
            end
            return 'ID', v
        end

        i = i + 1
        return c, nil
    end
end
