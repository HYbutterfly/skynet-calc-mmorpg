package.cpath = "luaclib/?.so;skynet/luaclib/?.so;"..package.cpath
local calc = require "skynet.calc"

local game = require "game".game
local gamex = require "game.extend"
local scenes = require "conf.scenes"

local Scene = require "gameclass.Scene"


-- init 
for i,s in ipairs(scenes) do
    game.scenes[s.id] = setmetatable(table.clone(s), {__index = Scene})
    game.scenes[s.id]:init()
end


local function exec(session, cmd, ...)
    local f = assert(game[cmd], string.format("Undefined action %s", tostring(cmd)))
    if session == 0 then
        f(...)
    else
        local r = f(...)
        return calc.pack(r, gamex:collect("socket_push"), gamex:collect("mongo_actions"))
    end
end


function handle(session, data, sz)
    return exec(session, calc.unpack(data, sz))
end

collectgarbage("stop")