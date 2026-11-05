-- Brings back what the client's own Lua can see of a login, for the playing-live skill: the
-- player's state, and the errors the addons raised. Once the character is loaded and its model is
-- in, it reloads the interface once: the client runs each addon's OnSave on a reload (fact
-- 0x1400446d0) and writes the Account-level table to AddonSaveData\GenesisReport_0_Acct.xml (facts
-- 0x140185f30, 0x1404240b0).
--
-- The saved table holds only tables, numbers, strings and booleans (fact 0x140185f30).
--
-- Timeline mode, when report.sh install --timeline wrote GenesisReportTimelineMinutes (and
-- GenesisReportInstalledAt, the PC's os.time() at the install) into GenesisReportAddons.lua: in
-- place of the one report, arTimeline gets one entry every second (strSource "poll") and one at
-- each UnitEnteredCombat event for the player (strSource "event", the event's flag in
-- bEventInCombat; the Medic bar's out-of-combat look follows that event, UI/ClassResources/
-- ClassResources.lua line 513). An entry holds nTime (os.time()), nGameTime (GameLib.GetGameTime(),
-- the client's own clock in seconds, as UI/NCCB/NonCombatCastBar.lua line 90 reads it), and from
-- the player unit bInCombat (Unit:IsInCombat(), fact 0x140653ed0), nResource (GetResource(1), fact
-- 0x14064fdb0) and nMaxResource (GetMaxResource(1), fact 0x140650300); with no player unit only
-- bPlayerUnit = false. The file is written only when the client runs OnSave (facts 0x140539640,
-- 0x1400446d0): on a reload and when the world is torn down. This addon asks for a reload when the
-- timeline is GenesisReportTimelineMinutes long and once the player has been out of combat for
-- knQuietSeconds after a fight; a person's /reloadui also writes it. The restored timeline is kept
-- and appended to after a reload of the same install; one saved by another install (its
-- nInstalledAt is not GenesisReportInstalledAt) is dropped, so a new install starts a new timeline
-- even when the old report file is still there. Whether closing the client's window runs OnSave is
-- not traced, so a timeline is not relied on to survive it.

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
	arTimeline = {},
	bTimelineFinished = false,
}

local knPollSeconds = 1.0
local knReadySeconds = 10
local knQuietSeconds = 30

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

-- Whether install --timeline asked for the timeline.
local function IsTimeline()
	return type(GenesisReportTimelineMinutes) == "number"
end

function GenesisReport:OnLoad()
	Apollo.RegisterEventHandler("LuaError", "OnLuaError", self)
	if IsTimeline() then
		Apollo.RegisterEventHandler("UnitEnteredCombat", "OnUnitEnteredCombat", self)
	end
	self.timerPoll = ApolloTimer.Create(knPollSeconds, true, "OnPoll", self)
end

-- Fact 0x140185f30: the client asks for each level; only the Account level is saved. A report that
-- was restored is saved again unchanged, so a later reload never replaces it with the state after
-- the first one.
function GenesisReport:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Account then
		return nil
	end
	if IsTimeline() then
		return
		{
			bTimeline = true,
			bReported = #self.arTimeline > 0,
			nReportedAt = os.time(),
			nInstalledAt = NumberOrNil(GenesisReportInstalledAt),
			nTimelineMinutes = GenesisReportTimelineMinutes,
			nTimelineStartedAt = self.nTimelineStartedAt,
			bTimelineFinished = self.bTimelineFinished,
			arTimeline = self.arTimeline,
			tLuaErrorEvents = self.tLuaErrorEvents,
		}
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
	if IsTimeline() then
		if type(tData) == "table" and tData.bTimeline == true and type(tData.arTimeline) == "table"
			and NumberOrNil(tData.nInstalledAt) == NumberOrNil(GenesisReportInstalledAt) then
			self.arTimeline = tData.arTimeline
			self.nTimelineStartedAt = NumberOrNil(tData.nTimelineStartedAt)
			self.bTimelineFinished = tData.bTimelineFinished == true
			if type(tData.tLuaErrorEvents) == "table" then
				self.tLuaErrorEvents = tData.tLuaErrorEvents
			end
		end
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

-----------------------------------------------------------------------------------------------
-- Timeline
-----------------------------------------------------------------------------------------------

-- Appends one entry (see the header) to arTimeline and returns it. bEnteredCombat is the event's
-- flag, nil for a poll.
function GenesisReport:AppendTimelineEntry(strSource, bEnteredCombat)
	local tEntry = { nTime = os.time(), strSource = strSource }
	tEntry.nGameTime = NumberOrNil(GameLib.GetGameTime())
	if bEnteredCombat ~= nil then
		tEntry.bEventInCombat = bEnteredCombat and true or false
	end

	local unitPlayer = GameLib.GetPlayerUnit()
	tEntry.bPlayerUnit = unitPlayer ~= nil
	if unitPlayer ~= nil then
		tEntry.bInCombat = unitPlayer:IsInCombat() and true or false
		tEntry.nResource = NumberOrNil(unitPlayer:GetResource(1))
		tEntry.nMaxResource = NumberOrNil(unitPlayer:GetMaxResource(1))
	end
	table.insert(self.arTimeline, tEntry)
	return tEntry
end

-- The same unit test ClassResources makes (UI/ClassResources/ClassResources.lua line 371 handler).
function GenesisReport:OnUnitEnteredCombat(unitChanged, bInCombat)
	if self.bTimelineFinished or unitChanged ~= GameLib.GetPlayerUnit() then
		return
	end
	self:AppendTimelineEntry("event", bInCombat)
end

-- One poll of the timeline. The clock starts at the first entry, which is the world's start since
-- the client loads addons then (fact 0x140538fd0). RequestReloadUI makes the client write the file
-- (a user addon has no ReloadUI, fact 0x1400447f0).
function GenesisReport:OnTimelinePoll()
	if self.bTimelineFinished then
		self.timerPoll:Stop()
		return
	end

	local tEntry = self:AppendTimelineEntry("poll")
	local nNow = tEntry.nTime
	if self.nTimelineStartedAt == nil then
		self.nTimelineStartedAt = nNow
	end

	if nNow - self.nTimelineStartedAt >= GenesisReportTimelineMinutes * 60 then
		self.bTimelineFinished = true
		RequestReloadUI()
		return
	end

	if tEntry.bInCombat then
		self.bFoughtSinceSave = true
		self.nQuietSince = nil
	elseif tEntry.bPlayerUnit and self.bFoughtSinceSave then
		if self.nQuietSince == nil then
			self.nQuietSince = nNow
		end
		if nNow - self.nQuietSince >= knQuietSeconds then
			self.bFoughtSinceSave = false
			self.nQuietSince = nil
			RequestReloadUI()
		end
	end
end

-- Fact 0x1406f6800: IsCharacterLoaded is true once every world-loading stage has passed.
-- RequestReloadUI: a user addon has no ReloadUI (fact 0x1400447f0).
function GenesisReport:OnPoll()
	if IsTimeline() then
		self:OnTimelinePoll()
		return
	end

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
