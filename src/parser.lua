-- luacheck: ignore 212

local Lex = require 'lex'
local Util = require 'util'

local to_hash = Util.to_hash
local sf = string.format
-- local concat = Util.concat

local UNOPR = { 'not', '-', '~', '#' }
local BINOPR = {
    { '+', 10, 10 },
    { '-', 10, 10 },
    { '*', 11, 11 },
    { '%', 11, 11 },
    { '^', 14, 13 },
    { '/', 11, 11 },
    { '//', 11, 11 },
    { '&', 6, 6 },
    { '|', 4, 4 },
    { '~', 5, 5 },
    { '<<', 7, 7 },
    { '>>', 7, 7 },
    { '..', 9, 8 },
    { '~=', 3, 3 },
    { '==', 3, 3 },
    { '<', 3, 3 },
    { '<=', 3, 3 },
    { '>', 3, 3 },
    { '>=', 3, 3 },
    { 'and', 2, 2 },
    { 'or', 1, 1 },
}
local CLOSE_BLOCK = { 'else', 'elseif', 'end', 'EOS', 'until' }
-- local CLOSE_SCOPE = { 'else', 'elseif', 'end', 'EOS' }

local IS_UNOPR = to_hash(UNOPR)
local IS_CLOSE_BLOCK = to_hash(CLOSE_BLOCK)
-- local IS_CLOSE_SCOPE = to_hash(CLOSE_SCOPE)

local BINOPR_HASH = {}
for _, v in ipairs(BINOPR) do
    BINOPR_HASH[v[1]] = { left=v[2], right=v[3] }
end

local UNARY_PRIORITY = 12

----

local expr
local block

local function newinfo(e)
    return {
        filename = e:get_filename(),
        line = e:get_line_no(),
    }
end

local function check_identifier(e)
    e:check_save('ID', true)
    return { tag='Id', info=e.info, e.cv }
end

-- primaryexp -> NAME | '(' expr ')'
local function primaryexp(e)
    if e:try_skip('(') then
        local n = expr(e)
        e:check_skip(')')
        return n
    elseif e.tt == 'ID' then
        return check_identifier(e)
    else
        e:syntax_error('unexpected symbol')
    end
end

-- constructor -> '{' [ field { sep field } [sep] ] '}'
-- sep -> ',' | ';'
local function constructor(e)
    local n = { tag='Table', info=newinfo(e) }
    local i = 0
    e:check_skip('{')
    while true do
        if e.tt == '}' then
            break
        end

        if e.tt == 'ID' then
            local info = newinfo(e)
            e:look_ahead()
            if e.at ~= '=' then
                i = i + 1
                n[#n+1] = { tag='Integer', info=info, i }
                n[#n+1] = expr(e)
            else
                n[#n+1] = { tag='Id', info=newinfo(e), e.tv }
                e:next_token()
                e:check_skip('=')
                n[#n+1] = expr(e)
            end
        elseif e:try_skip('[') then
            n[#n+1] = expr(e)
            e:check_skip(']')
            e:check_skip('=')
            n[#n+1] = expr(e)
        else
            local info = newinfo(e)
            i = i + 1
            n[#n+1] = { tag='Integer', info=info, i }
            n[#n+1] = expr(e)
        end

        if not (e:try_skip(',') or e:try_skip(';')) then
            break
        end
    end
    e:check_skip('}')
    return n
end

local function explist(e)
    local n = { tag='ExpList', info=newinfo(e) }
    repeat
        n[#n+1] = expr(e)
    until not e:try_skip(',')
    return n
end

local function funcargs(e, n_funcname)
    local info = newinfo(e)
    if e:try_skip('(') then
        if e:try_skip(')') then
            local n_parlist = { tag='ExpList', info=info }
            return { tag='Call', info=info, n_funcname, n_parlist }
        else
            local n_parlist = explist(e)
            e:check_skip(')')
            return { tag='Call', info=info, n_funcname, n_parlist }
        end
    elseif e.tt == '{' then
        local n_parlist = { tag='ExpList', info=info, constructor(e) }
        return { tag='Call', info=info, n_funcname, n_parlist }
    elseif e:try_save('STR', true) then
        local n_parlist = { tag='ExpList', info=info, { tag='Str', info=info, e.cv } }
        return { tag='Call', info=info, n_funcname, n_parlist }
    else
        e:syntax_error('function arguments expected')
    end
end

-- suffixedexp -> primaryexp { '.' NAME | '[' exp ']' | ':' NAME funcargs | funcargs }
local function suffixedexp(e)
    local n1 = primaryexp(e)

    while true do
        if e:try_skip('.') then
            local n2 = check_identifier(e)
            n1 = { tag='IndexShort', info=newinfo(e), n1, n2 }
        elseif e:try_skip('[') then
            local n2 = expr(e)
            e:check_skip(']')
            n1 = { tag='Index', info=newinfo(e), n1, n2 }
        elseif e:try_skip(':') then
            e:check_save('ID', true)
            local n2 = { tag='Id', info=newinfo(e), e.cv }
            n1 = { tag='Invoke', info=newinfo(e), n1, n2 }
            n1 = funcargs(e, n1)
        elseif e.tt == '(' or e.tt == 'STR' or e.tt == '{' then
            n1 = funcargs(e, n1)
        else
            break
        end
    end

    return n1
end

-- parlist -> [ {NAME ','} (NAME | '...') ]
local function parlist(e)
    local n_namelist = { tag='NameList', info=newinfo(e) }
    while e.tt ~= ')' do
        if e.tt == 'ID' then
            n_namelist[#n_namelist+1] = check_identifier(e)
            if not e:try_skip(',') then
                break
            end
        elseif e:try_skip('...') then
            n_namelist[#n_namelist+1] = { tag='VarArg', info=newinfo(e) }
            break
        else
            e:syntax_error("<name> or '...' expected")
        end
    end
    return n_namelist
end

-- body ->  '(' parlist ')' block END
local function body(e)
    e:check_skip('(')
    local n_parlist = parlist(e)
    e:check_skip(')')
    local n_block = block(e)
    e:check_skip('end')
    return n_parlist, n_block
end

local function simpleexp(e)
    if e:try_save('FLT', true) then
        return { tag='Float', info=newinfo(e), e.cv }
    elseif e:try_save('INT', true) then
        return { tag='Integer', info=newinfo(e), e.cv }
    elseif e:try_save('STR', true) then
        return { tag='Str', info=newinfo(e), e.cv }
    elseif e:try_skip('nil') then
        return { tag='Nil', info=newinfo(e) }
    elseif e:try_skip('true') then
        return { tag='Bool', info=newinfo(e), true }
    elseif e:try_skip('false') then
        return { tag='Bool', info=newinfo(e), false }
    elseif e:try_skip('...') then
        return { tag='VarArg', info=newinfo(e) }
    elseif e.tt == '{' then
        return constructor(e)
    elseif e:try_skip('function') then
        local info = e.info
        local n_parlist, n_block = body(e)
        return { tag='Function', info=info, n_parlist, n_block }
    else
        return suffixedexp(e)
    end
end

local function subexpr(e, limit)
    local n1
    if IS_UNOPR[e.tt] then
        local op = e.tt
        e:next_token()
        local n2 = subexpr(e, UNARY_PRIORITY)
        n1 = { tag='UnOpr', info=newinfo(e), op, n2 }
    else
        n1 = simpleexp(e)
    end

    local binopr = BINOPR_HASH[e.tt]
    while binopr and binopr.left > limit do
        local op = e.tt
        local info = newinfo(e)
        e:next_token()
        local n2, next_binopr = subexpr(e, binopr.right)
        n1 = { tag='BinOpr', info=info, op, n1, n2 }
        binopr = next_binopr
    end

    return n1, binopr
end

expr = function(e)
    return subexpr(e, 0)
end

local function localfunc(e)
    local info = newinfo(e)
    local n_id = check_identifier(e)
    local n_parlist, n_block = body(e)
    return { tag='LocalFunctionDef', info=info, n_id, n_parlist, n_block }
end

local function localstat(e)
    local info = newinfo(e)
    local n_namelist = { tag='NameList', info=info }
    repeat
        n_namelist[#n_namelist+1] = check_identifier(e)
    until not e:try_skip(',')

    local expr_list
    if e:try_skip('=') then
        expr_list = explist(e)
    else
        expr_list = { tag='ExpList', info=info }
    end

    return { tag='Local', info=info, n_namelist, expr_list }
end

-- funcname -> NAME {fieldsel} [':' NAME] */
local function funcname(e)
    local node = { tag='FuncName', info=newinfo(e), invoke=false }
    node[#node+1] = check_identifier(e)
    while e:try_skip('.') do
        node[#node+1] = check_identifier(e)
    end
    if e:try_skip(':') then
        node[#node+1] = check_identifier(e)
        node.invoke = true
    end
    return node
end

-- funcstat -> FUNCTION funcname body
local function funcstat(e)
    local n_funcname = funcname(e)
    local n_parlist, n_block = body(e)
    return { tag='FunctionDef', info=newinfo(e), n_funcname, n_parlist, n_block }
end

-- stat -> func | assignment
local function exprstat(e)
    local info = newinfo(e)
    local n1 = suffixedexp(e)
    if e.tt == '=' or e.tt == ',' then
        local n_namelist = { tag='ExpList', info=info, n1 }
        while e:try_skip(',') do
            n_namelist[#n_namelist+1] = suffixedexp(e)
        end
        e:check_skip('=')
        local expr_list = explist(e)
        return { tag='Set', info=info, n_namelist, expr_list }
    else
        -- stat -> func
        if n1.tag ~= 'Call' then
            e:syntax_error('syntax error')
        end
        return n1
    end
end

-- ifstat -> IF cond THEN block {ELSEIF cond THEN block} [ELSE block] END
local function ifstat(e)
    local node = { tag='If', info=newinfo(e) }
    node[#node+1] = expr(e)
    e:check_skip('then')

    node[#node+1] = block(e)

    while e:try_skip('elseif') do
        node[#node+1] = expr(e)
        e:check_skip('then')

        node[#node+1] = block(e)
    end

    if e:try_skip('else') then
        node[#node+1] = { tag='Bool', info=e.info, true }
        node[#node+1] = block(e)
    end

    e:check_skip('end')

    return node
end

-- stat -> RETURN [explist] [';']
local function retstat(e)
    local n = { tag='Return', info=newinfo(e) }
    if e:try_skip(';') then
        return n
    elseif IS_CLOSE_BLOCK[e.tt] then
        return n
    else
        n[#n+1] = explist(e)
        e:try_skip(';')
        return n
    end
end

local function fornum(e, n_var1)
    local info = newinfo(e)
    local n1 = expr(e)
    e:check_skip(',')
    local n2 = expr(e)
    local n3
    if e:try_skip(',') then
        n3 = expr(e)
    else
        n3 = nil
    end
    e:check_skip('do')
    local n_block = block(e)
    e:check_skip('end')
    return { tag='Fornum', info=info, n_var1, n1, n2, n3, n_block }
end

local function forlist(e, n_var1)
    local info = newinfo(e)
    local n_namelist = { tag='NameList', info=newinfo(e), n_var1 }
    while e:try_skip(',') do
        n_namelist[#n_namelist+1] = check_identifier(e)
    end
    e:check_skip('in')
    local n_expr_list = explist(e)
    e:check_skip('do')
    local n_block = block(e)
    e:check_skip('end')
    return { tag='Forin', info=info, n_namelist, n_expr_list, n_block }
end

local typeexp

local function typetable(e, open)
    local keys = {}
    local hash = {}
    local n_tpobj = { tag='TypeObj', info=newinfo(e), keys=keys, hash=hash, open=open }
    e:check_skip('{')
    while true do
        if e:try_skip('}') then
            break
        end

        local n_fieldname = check_identifier(e)
        e:check_skip(':')
        local n_fieldtype = typeexp(e)
        e:check_skip(';')

        local field = n_fieldname[1]
        keys[#keys+1] = field
        hash[field] = n_fieldtype
        -- table.insert(n_tpobj, n_fieldname)
        -- table.insert(n_tpobj, n_fieldtype)
    end
    return n_tpobj
end

local function primarytype(e)
    local n
    local info = newinfo(e)
    if e.tt == 'ID' and e.tv == 'open' then
        e:next_token()
        n = typetable(e, true)
    elseif e.tt == '{' then
        n = typetable(e, false)
    elseif e:try_skip('(') then
        n = typeexp(e)
        e:check_skip(')')
    elseif e.tt == 'ID' then
        n = check_identifier(e)
    elseif e:try_skip('...') then
        return { tag='VarArg', info=e.info }
    else
        e:syntax_error(sf("'ID' expected"))
        return { tag='ID', info=newinfo(e), 'Any' }
    end

    if e:try_skip('?') then
        n = { tag='OptArg', info=info, n }
    end

    return n
end

-- 返回一个 Type
typeexp = function(e)
    local info = newinfo(e)

    local n = primarytype(e)

    -- 不是 TypeFunction
    if e.tt ~= ',' and e.tt ~= '>>' then
        return n
    end

    -- 是 TypeFunction

    local n_args = { tag='TypeArgList', info=info, n }

    while e:try_skip(',') do
        n_args[#n_args+1] = primarytype(e)
    end

    e:check_skip('>>')

    local n_ret = primarytype(e)
    return { tag='TypeFunction', info=info, n_args, n_ret }
end

local function typesuffixedname(e)
    local n1 = check_identifier(e)

    while true do
        if e:try_skip('.') then
            local n2 = check_identifier(e)
            n1 = { tag='IndexShort', info=newinfo(e), n1, n2 }
        else
            break
        end
    end

    return n1
end

local function typestatement(e)
    local info = newinfo(e)

    if e.tt == 'ID' and e.tv == 'open' then
        e:next_token()
        local n_id = typesuffixedname(e)
        return  { tag='OpenTypeObj', info=info, n_id }
    end

    if e.tt == 'ID' and e.tv == 'close' then
        e:next_token()
        local n_id = typesuffixedname(e)
        return  { tag='CloseTypeObj', info=info, n_id }
    end

    -- local n_id = check_identifier(e)
    local n_id = typesuffixedname(e)
    if e:try_skip('=') then
        local n_type = typeexp(e)
        return { tag='Tpdef', info=info, n_id, n_type }
    else
        e:check_skip('::')
        local n_type = typeexp(e)
        return { tag='Tpbind', info=info, n_id, n_type }
    end
end

local function statement(e)
    if e:try_skip(';') then
        return { tag='EmptyStat', info=e.info }
    elseif e:try_skip('if') then
        return ifstat(e)
    elseif e:try_skip('while') then
        local info = e.info
        local n_cond = expr(e)
        e:check_skip('do')
        local n_block = block(e)
        e:check_skip('end')
        return { tag='While', info=info, n_cond, n_block }
    elseif e:try_skip('do') then
        local info = e.info
        local n_block = block(e)
        local n_do = { tag='Do', info=info, n_block }
        e:check_skip('end')
        return n_do
    elseif e:try_skip('for') then
        local n_var1 = check_identifier(e)
        if e:try_skip('=') then
            return fornum(e, n_var1)
        elseif e.tt == ',' or e.tt == 'in' then
            return forlist(e, n_var1)
        else
            e:syntax_error("'=' or 'in' expected")
        end
    elseif e:try_skip('repeat') then
        local info = e.info
        local n_block = block(e)
        e:check_skip('until')
        local n_cond = expr(e)
        return { tag='Repeat', info=info, n_block, n_cond }
    elseif e:try_skip('function') then
        return funcstat(e)
    elseif e:try_skip('local') then
        if e:try_skip('function') then
            return localfunc(e)
        else
            return localstat(e)
        end
    elseif e:try_skip('::') then
        local n_label = { tag='Label', info=e.info, check_identifier(e) }
        e:check_skip('::')
        return n_label
    elseif e:try_skip('return') then
        return retstat(e)
    elseif e:try_skip('break') then
        return { tag='Break', info=e.info }
    elseif e:try_skip('goto') then
        return { tag='Goto', info=e.info, check_identifier(e) }

    -- 类型检查用
    elseif e:try_skip('TPLINE') then
        return typestatement(e)
    elseif e:try_skip('TPDEF_BEGIN') then
        local n = { tag='Tpblock', info= e.info }
        while true do
            if e:try_skip('TPDEF_END') then
                break
            end
            n[#n+1] = typestatement(e)
        end
        return n

    else
        return exprstat(e)
    end
end

block = function(e)
    local n = { tag='Block', info=newinfo(e) }
    while not IS_CLOSE_BLOCK[e.tt] do
        if e.tt == 'return' then
            n[#n+1] = statement(e)
            break
        end
        n[#n+1] = statement(e)
    end
    return n
end

local function mainfunc(e)
    local n = block(e)
    e:check_skip('EOS')
    return n
end

return function(c, s, is_file)
    -- local function hook()
    --     error('infinite loop detected\n' .. s)
    -- end
    -- debug.sethook(hook, '', 10000000)

    -- print('================================================ s:', s)
    -- local f = io.open(s, 'r')
    -- if not f then
    --     io.stderr:write("file not found: " .. s .. "\n")
    --     return nil
    -- end
    -- local c = f:read('a')
    -- f:close()

    local get_next_token = Lex(c, s, is_file)

    local e = {
        tt = nil,
        tv = nil,
        cv = nil,  -- checked value
        lookahead = false,
        at = nil,  -- look ahead
        av = nil,  -- look ahead
    }

    function e:get_filename()
        return s
    end

    function e:get_line_no()
        return get_next_token('LINE_NO')
    end

    function e:next_token()
        local tt, tv
        if self.lookahead then
            self.lookahead = false
            tt = self.at
            tv = self.av
        else
            tt, tv = get_next_token()
        end
        -- print('TOKEN', tt, tv)
        self.tt = tt
        self.tv = tv
    end

    function e:look_ahead()
        if not self.lookahead then
            local tt, tv = get_next_token()
            self.lookahead = true
            self.at = tt
            self.av = tv
        end
    end

    function e:try_skip(tt)
        if self.tt == tt then
            self.info = newinfo(self)
            self:next_token()
            return true
        else
            return false
        end
    end

    function e:try_save(tt, consume)
        return self:check_save(tt, consume, true)
    end

    function e:check_skip(tt)
        if self.tt == tt then
            self:next_token()
        else
            print(debug.traceback())
            self:syntax_error(sf("'%s' expected", tt))
        end
    end

    function e:check_save(tt, consume, noerr)
        if self.tt ~= tt then
            if not noerr then
                print(debug.traceback())
                self:syntax_error(sf("'%s' expected", tt))
            end
            return false
        end

        self.cv = self.tv
        self.info = newinfo(self)

        if consume then
            self:next_token()
        end
        return true
    end

    function e:syntax_error(msg)
        print(sf('%s:%d: (syntax_error) %s (near %s)', self:get_filename(), self:get_line_no(), msg, self:dump_token()))
        coroutine.yield('__SYNTAX_ERROR__')
    end

    function e:dump_token()
        if self.tt == 'ID' then
            return sf('ID<%s>', self.tv)
        elseif self.tt == 'STR' then
            return sf('string<%s>', self.tv)
        elseif self.tt == 'INT' then
            return sf('Integer<%s>', self.tv)
        elseif self.tt == 'FLT' then
            return sf('Float<%s>', self.tv)
        elseif self.tt == 'EOS' then
            return '<eof>'
        elseif self.tt == 'TPLINE' then
            return '(-->>)'
        else
            return sf('<%s>', self.tt)
        end
    end

    local co = coroutine.create(function()
        e:next_token()
        return mainfunc(e)
    end)
    local ok, v = coroutine.resume(co)
    if not ok then
        error(debug.traceback(co, v))
    end
    if v == '__SYNTAX_ERROR__' then
        return nil
    end

    return v
end
