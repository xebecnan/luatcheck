
local MFC = require 'test_module_func_check'

-- ok
MFC.strlen('str')

-- error
MFC.strlen(42)
MFC.strlen('str', 42)
MFC.strlen()
MFC.func_not_exist()
