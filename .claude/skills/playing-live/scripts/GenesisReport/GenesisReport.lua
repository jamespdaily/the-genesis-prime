-- Brings back what the client's own Lua can see of a login, for the playing-live skill: the
-- player's state, and the errors the addons raised. Once the character is loaded and its model is
-- in, it reloads the interface once: the client runs each addon's OnSave on a reload (fact
-- 0x1400446d0) and writes the Account-level table to AddonSaveData\GenesisReport_0_Acct.xml (facts
-- 0x140185f30, 0x1404240b0).
--
-- The saved table holds only tables, numbers, strings and booleans (fact 0x140185f30).

require "Apollo"
require "GameLib"
require "PlayerPathLib"
require "Unit"

local GenesisReport =
{
	nPolls = 0,
	tReport = {},
	tLuaErrorEvents = {},
	bReloadAsked = false,
}

local knPollSeconds = 1.0
local knReadySeconds = 10

function GenesisReport:Init()
	Apollo.RegisterAddon(self)
end

-- The strings of a list, as a new list of text (arErrors holds each error's text, 1-based; facts
-- 0x14013c8b0, 0x1400ea7b0).
local function CopyTexts(arTexts)
	local arCopy = {}
	if type(arTexts) == "table" then
		for idx, strText in ipairs(arTexts) do
			arCopy[idx] = tostring(strText)
		end
	end
	return arCopy
end

local function NumberOrNil(value)
	if type(value) == "number" then
		return value
	end
	return nil
end

-----------------------------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------------------------

-- Fact 0x1400ea7b0: LuaError handlers get (tAddon, strError, bCanIgnore); tAddon.arErrors holds every
-- error the addon has had so far, and strName is read from it by the ErrorDialog addon.
function GenesisReport:OnLuaError(tAddon, strError, bCanIgnore)
	local tEvent =
	{
		strAddon = "",
		strError = tostring(strError),
		bCanIgnore = bCanIgnore and true or false,
		arErrors = {},
	}
	if type(tAddon) == "table" then
		tEvent.strAddon = tostring(tAddon.strName)
		tEvent.arErrors = CopyTexts(tAddon.arErrors)
	end
	table.insert(self.tLuaErrorEvents, tEvent)
end

function GenesisReport:OnLoad()
	Apollo.RegisterEventHandler("LuaError", "OnLuaError", self)
	self.timerPoll = ApolloTimer.Create(knPollSeconds, true, "OnPoll", self)
end

-- Fact 0x140185f30: the client asks for each level; only the Account level is saved. A report that
-- was restored is saved again unchanged, so a later reload never replaces it with the state after
-- the first one.
function GenesisReport:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Account then
		return nil
	end
	if self.tRestored ~= nil then
		return self.tRestored
	end

	self.tReport.bReported = self.nReportedAt ~= nil
	self.tReport.nReportedAt = self.nReportedAt
	self.tReport.tLuaErrorEvents = self.tLuaErrorEvents
	return self.tReport
end

-- A report kept from before the reload is never replaced and never reloads again.
function GenesisReport:OnRestore(eLevel, tData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Account then
		return
	end
	if type(tData) == "table" and tData.bReported == true then
		self.tRestored = tData
	end
end

-----------------------------------------------------------------------------------------------
-- Polling
-----------------------------------------------------------------------------------------------

-- The player unit's values into tReport. Facts: 0x1406f6560 (GetPlayerUnit, nil without a player),
-- 0x1406535f0 (IsDead), 0x14064a4e0 (GetHealth), 0x14064a6d0 (GetMaxHealth), 0x140651c90
-- (GetPosition, a table read as .x .y .z), 0x1406f6780 (IsControlledUnit), 0x140651bd0 (GetName),
-- 0x140653210 (GetLevel). A value the client answers with nil is left out of the report. Returns
-- whether the unit's model is loaded: GetOverheadAnchor is nil until it is (fact 0x140659ce0).
function GenesisReport:ReadPlayer(tReport)
	local unitPlayer = GameLib.GetPlayerUnit()
	tReport.bPlayerUnit = unitPlayer ~= nil
	if unitPlayer == nil then
		return false
	end

	tReport.bDead = unitPlayer:IsDead() and true or false
	tReport.nHealth = NumberOrNil(unitPlayer:GetHealth())
	tReport.nMaxHealth = NumberOrNil(unitPlayer:GetMaxHealth())
	tReport.bControlled = GameLib.IsControlledUnit(unitPlayer) and true or false
	tReport.strName = tostring(unitPlayer:GetName())
	tReport.nLevel = NumberOrNil(unitPlayer:GetLevel())

	local tPosition = unitPlayer:GetPosition()
	if type(tPosition) == "table" then
		tReport.tPos =
		{
			x = NumberOrNil(tPosition.x),
			y = NumberOrNil(tPosition.y),
			z = NumberOrNil(tPosition.z),
		}
	end

	local bModelLoaded = unitPlayer:GetOverheadAnchor() ~= nil
	tReport.bModelLoaded = bModelLoaded
	return bModelLoaded
end

-- Fact 0x1406f0740: PlayerPathLib.GetPlayerPathType() is nil before message 0x6bc arrives, so ePath
-- is left out of the report then, and never saved as a number that stands for none.
function GenesisReport:ReadPath(tReport)
	local ePath = PlayerPathLib.GetPlayerPathType()
	if type(ePath) == "number" then
		tReport.ePath = ePath
	end
end

-- Facts 0x14013c8b0 and 0x140137120: Apollo.GetAddonInfo(strName).arErrors lists every error the
-- addon has had, including those raised before this addon loaded; nil for a name the interface does
-- not have; those names are listed in arAddonsWithoutInfo. GenesisReportAddons is the list of names
-- to sweep, loaded from GenesisReportAddons.lua before this file.
function GenesisReport:SweepAddonErrors(tReport)
	local tAddonErrors = {}
	local arWithoutInfo = {}
	local arNames = GenesisReportAddons
	if type(arNames) ~= "table" then
		arNames = {}
	end
	for _, strName in ipairs(arNames) do
		local tInfo = Apollo.GetAddonInfo(strName)
		if type(tInfo) ~= "table" then
			table.insert(arWithoutInfo, strName)
		elseif type(tInfo.arErrors) == "table" and #tInfo.arErrors > 0 then
			tAddonErrors[strName] = CopyTexts(tInfo.arErrors)
		end
	end
	tReport.tAddonErrors = tAddonErrors
	tReport.arAddonsWithoutInfo = arWithoutInfo
end

-- Fact 0x1406f6800: IsCharacterLoaded is true once every world-loading stage has passed.
-- RequestReloadUI: a user addon has no ReloadUI (fact 0x1400447f0).
function GenesisReport:OnPoll()
	if self.tRestored ~= nil then
		self.timerPoll:Stop()
		return
	end

	self.nPolls = self.nPolls + 1
	local nNow = os.time()
	local tReport = { nPolls = self.nPolls, nTime = nNow }
	tReport.bCharacterLoaded = GameLib.IsCharacterLoaded() and true or false
	local bModelLoaded = self:ReadPlayer(tReport)
	self:ReadPath(tReport)
	self:SweepAddonErrors(tReport)
	self.tReport = tReport

	if tReport.bCharacterLoaded and bModelLoaded then
		if self.nReadySince == nil then
			self.nReadySince = nNow
		end
		if not self.bReloadAsked and nNow - self.nReadySince >= knReadySeconds then
			self.bReloadAsked = true
			self.nReportedAt = nNow
			RequestReloadUI()
		end
	end
end

GenesisReport:Init()
