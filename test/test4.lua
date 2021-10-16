--[[>>
AstNode = {
    tag : string;
    info : any;
    scope : any;
}
<<]]

-->> walk :: AstNode >> boolean
local function walk(ast)
    return not not ast
end

walk({tag='', info={}, scope={}})
