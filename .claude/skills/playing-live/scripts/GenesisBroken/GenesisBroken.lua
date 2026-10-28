-- A deliberately broken addon, for the check that GenesisReport brings back an addon's errors. It
-- fails twice: in OnLoad, which may run before GenesisReport registers for LuaError (the sweep of
-- Apollo.GetAddonInfo(...).arErrors catches that one), and in a timer a few seconds later, after
-- GenesisReport has registered (the LuaError event catches that one). Each call is an addon Lua
-- function the client runs under its error handler (fact 0x1400f2730).

require "Apollo"

local GenesisBroken = {}

function GenesisBroken:Init()
	Apollo.RegisterAddon(self)
end

function GenesisBroken:OnLoad()
	self.timerLater = ApolloTimer.Create(3.0, false, "OnLater", self)
	GenesisBrokenNoSuchFunction()
end

function GenesisBroken:OnLater()
	GenesisBrokenNoSuchFunction()
end

GenesisBroken:Init()
