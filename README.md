# luatcheck
yet another lua static type checker :P

There are quite a few Lua static type checkers out there, but none of the existing ones exactly fit my needs, so I roll up my sleeves and write one myself~

This type checker works directly on the Lua code, with the extra type annotations written in a specific format in the comments, in its original format.

This project is still in early development, and I'll be refining it as I use it in my own daily work. Also learning the theory of type systems.

The source code can be packaged into a single Lua file using some tools, then packaged into an executable using tools such as [luastatic](https://github.com/ers35/luastatic/), and then integrated into the vim development environment using the ale(https://github.com/dense-analysis/ale) plugin to the vim development environment.
I've integrated a toolset for packaging, and a configuration file for integration into vim ale, but it's not fully sorted out yet, so maybe I can release it to a separate repo when it's sorted out later.


# luatcheck
又一个 Lua 静态类型检查器 :P

Lua 静态类型检查工具已经有不少了，但是现有的都不完全符合我的需要，所以我还是自己撸起袖子写一个吧~

这个类型检查器直接工作在原格式的 Lua 源码上，额外的类型标记以特定的格式写在注释中。

这个项目还在早起开发中，我将一边在自己的日常工作中使用，一边完善它。同时学习类型系统的理论。

可以用工具将源码打包到单个 Lua 文件，然后用 [luastatic](https://github.com/ers35/luastatic/) 等工具打包为可执行文件，再通过 [ale](https://github.com/dense-analysis/ale) 插件集成到 vim 开发环境中。
我自己整合了一个打包工具集，和集成到 vim ale 用的配置文件，不过还没有完全整理好，或许晚点整理好后可以发布到单独的 repo 中。

## examples

```lua
-->> add :: number, number >> number
local function add(a, b)
  return a + b
end

-->> strlen :: string >> number
local strlen(s)
  return #s
end
```
