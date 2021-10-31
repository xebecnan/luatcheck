--[[>>
AstNode = {
    tag : string;
    info : any;
    scope : any;
}
<<]]

-->> add :: number, number >> number
local function add(a, b)
    return a + b
end

--------------------------------
-- ERROR
--------------------------------

-->> var1 :: AstNode
local var1 = 'test'

-->> var2 :: { b : number; }
local var2 = { }

-->> var3 :: { b : number; }
local var3 = { b = true }

-->> var4 :: { b : number; }
local var4 = { b = 42, c = 42 }

add(var1, 2)

--------------------------------
-- OK
--------------------------------

-->> var5 :: { b : number; }
local var5 = { b = 42 }

-->> var6 :: { b : number; }
local var6 = { b = 3.14159 }

print(var1, var2, var3, var4, var5, var6)
