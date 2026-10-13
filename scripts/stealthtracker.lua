--[[  FEATURE TODO
    For feature on token hover to display a panel with StealthTracker info (from CoreRPG):
		if TokenManager2 and TokenManager2.onHover then
			TokenManager2.onHover(tokenMap, nodeCT, bOver);
		end
--]]
local ALL = "all"
local AWARE = "aware"
local DEXTERITY = "dexterity"
local EFFECTS = "effects"
local FORCE_DISPLAY = true
local GENACTROLL = "genactroll"
local HIDDEN = "hidden"
IS_FGC = false
local LAST_DRAG_INFO = nil
local LAST_NODE_NAME = nil
local LAST_NODE_TYPE = nil
local LOCALIZED_DEXTERITY = "Dexterity"
local LOCALIZED_DEXTERITY_LOWER = LOCALIZED_DEXTERITY:lower()
local LOCALIZED_STEALTH = "Stealth"
local LOCALIZED_STEALTH_ABV = "S"
local LOCALIZED_STEALTH_LOWER = LOCALIZED_STEALTH:lower()
local NONE = "none"
local OFF = "off"
local ON = "on"
local OOB_MSGTYPE_UPDATESTEALTH = "updatestealth"
local OOB_MSGTYPE_ATTACKFROMSTEALTH = "attackfromstealth"
local SECRET = true
local ST_STEALTH_DISABLED_OUT_OF_FORMAT = "Stealth processing disabled when out of %s."
local STEALTHTRACKER_ALLOW_OUT_OF = "STEALTHTRACKER_ALLOW_OUT_OF"
local STEALTHTRACKER_AWARE = "STEALTHTRACKER_AWARE"
local STEALTHTRACKER_EXPIRE_EFFECT = "STEALTHTRACKER_EXPIRE_EFFECT"
local STEALTHTRACKER_FACTION_FILTER = "STEALTHTRACKER_FACTION_FILTER"
local STEALTHTRACKER_FRAME_STYLE = "STEALTHTRACKER_FRAME_STYLE"
local STEALTHTRACKER_INIT_CLEAR = "STEALTHTRACKER_INIT_CLEAR"
local STEALTHTRACKER_SHOW_AFTER_STEALTH = "STEALTHTRACKER_SHOW_AFTER_STEALTH"
local STEALTHTRACKER_SHOW_EYE = "STEALTHTRACKER_SHOW_EYE"
local STEALTHTRACKER_VERBOSE = "STEALTHTRACKER_VERBOSE"
local STEALTHTRACKER_VISIBLE = "STEALTHTRACKER_VISIBLE"
local STEALTHTRACKER_VISIBILITY = "STEALTHTRACKER_VISIBILITY"
local TURN = "turn"
local UNAWARE = "unaware"
local UNIDENTIFIED = "(unidentified)"
local USER_ISHOST = false
local VISIBLE = "visible"

-- Configuration table for stealth effects to apply to observers
local STEALTH_EFFECT_MODIFIERS = {
    ["cloak of elvenkind"] = -5
}

local A_CHECK_FILTER = {
    "wisdom"
}
local A_SKILL_FILTER = {
    "perception",
    "wisdom"
}

aOwnResultWrappers = {}
local ActionsManager_performAction_Original, CombatManager_onDrop, CombatManager_requestActivation
local _bAbilityBonusWarningLogged = false
bStealthTrackerInitialized = false

-- Helper to safely check if a string is blank, preferring the modern StringManager method.
local function isBlankSafe(s)
    if StringManager.isBlank then
        return StringManager.isBlank(s)
    end
    if type(s) ~= "string" then
        return false
    end
    return (string.gsub(s, "%s+", "") == "")
end

-- Helper to safely fetch ability bonuses from the 5E ruleset, with a one-time console warning if the API is missing.
local function getAbilityBonusSafe(nodeActor, sAbility)
    if ActorManager5E and ActorManager5E.getAbilityBonus then
        return ActorManager5E.getAbilityBonus(nodeActor, sAbility)
    end

    if not _bAbilityBonusWarningLogged then
        Debug.console("StealthTracker: Warning - ActorManager5E.getAbilityBonus not found. Defaulting to +0 mod. Please check for ruleset compatibility.")
        _bAbilityBonusWarningLogged = true
    end
    return 0
end

-- Helper to safely check for effects, preferring 5E-specific EffectManager if available.
local function hasEffectSafe(rActor, sEffect, rTarget, bTargetedOnly)
    if EffectManager5E and EffectManager5E.hasEffect then
        return EffectManager5E.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    if EffectManager and EffectManager.hasEffect then
        return EffectManager.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    return false
end

-- Helper to safely get effects by type, preferring 5E-specific EffectManager if available.
local function getEffectsByTypeSafe(nodeActor, sEffectType, aFilter, rTarget, bTargetedOnly)
    if EffectManager5E and EffectManager5E.getEffectsByType then
        return EffectManager5E.getEffectsByType(nodeActor, sEffectType, aFilter, rTarget, bTargetedOnly)
    end
    if EffectManager and EffectManager.getEffectsByType then
        return EffectManager.getEffectsByType(nodeActor, sEffectType, rTarget, bTargetedOnly)
    end
    return {}
end

-- Helper to safely get effects bonus, preferring EffectManager5E if available.
local function getEffectsBonusSafe(nodeActor, aEffectTypes, bFirstOnly, aFilter)
    if EffectManager5E and EffectManager5E.getEffectsBonus then
        return EffectManager5E.getEffectsBonus(nodeActor, aEffectTypes, bFirstOnly, aFilter)
    end
    if bFirstOnly then
        return 0, 0
    end
    return {}, 0, 0
end

-- Helper to safely get ability effects bonus, preferring ActorManager5E if available.
local function getAbilityEffectsBonusSafe(nodeActor, sAbility)
    if ActorManager5E and ActorManager5E.getAbilityEffectsBonus then
        return ActorManager5E.getAbilityEffectsBonus(nodeActor, sAbility)
    end
    return 0, 0
end

-- Helper to safely get an actor from a node/string, preferring the modern getActor method.
-- Note: In FGC, ActorManager.getActor is a legacy 2-argument deprecated function (sActorOldType, v)
-- that returns resolveActor(v). Calling it with 1 argument passes v as nil, returning nil.
-- On FGC, resolveActor(v) must be used.
function getActorSafe(v)
    if IS_FGC or checkFGC() then
        return ActorManager.resolveActor(v)
    end
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

-- Helper to safely get an actor's type and node, preferring the modern getTypeAndNode method.
local function getTypeAndNodeSafe(v)
    if ActorManager.getTypeAndNode then
        return ActorManager.getTypeAndNode(v)
    end
    return ActorManager.getActorTypeAndNode(v)
end

-- Helper to safely capture the ruleset's existing result handler for a roll type.
-- ActionsManager.getResultHandler exists in FGU but not FGC, so fall back to the
-- internal handler table or ruleset action manager before defaulting to nil.
local function getResultHandlerSafe(sType)
    if ActionsManager.getResultHandler then
        return ActionsManager.getResultHandler(sType)
    end
    local aHandlers = ActionsManager.aRollHandlers or ActionsManager.aHandlers
    if type(aHandlers) == "table" and type(aHandlers[sType]) == "table" then
        return aHandlers[sType].fResultHandler
    end
    if sType == "skill" and ActionSkill and ActionSkill.onRoll then
        return ActionSkill.onRoll
    elseif sType == "attack" and ActionAttack and ActionAttack.onAttack then
        return ActionAttack.onAttack
    end
    return nil
end

-- Helper to check if advantage/disadvantage has already been decoded on a roll (e.g. by Generic Actions or ruleset).
local function isRollAdvantageDecoded(rRoll)
	if not rRoll then return true end
	if rRoll.bAdvantageDecoded then return true end
	if rRoll.sGenericAction ~= nil then return true end
	local sType = (rRoll.sType or ""):lower()
	if sType == GENACTROLL then return true end
	local sDesc = rRoll.sDesc or ""
	if sDesc:lower():match("%[dropped") then
		return true
	end
	return false
end

-- Helper to safely extract database node path from a databasenode (userdata/databasenode in FGU), mock table, or string.
local function getNodePathSafe(vNode)
	if not vNode then return nil end
	if type(vNode) == "string" then
		return (vNode ~= "" and vNode) or nil
	end
	if (type(vNode) == "userdata" or type(vNode) == "table" or type(vNode) == "databasenode") and vNode.getPath then
		local bOk, sPath = pcall(vNode.getPath, vNode)
		if bOk and sPath and sPath ~= "" then return sPath end
	end
	if DB and DB.getPath then
		local bOk, sPath = pcall(DB.getPath, vNode)
		if bOk and sPath and sPath ~= "" then return sPath end
	end
	return nil
end

-- This function is required for all extensions to initialize variables and spit out the copyright and name of the extension as it loads
function onInit()
	-- Guard against onInit() running more than once in the same session (e.g. a script/extension
	-- reload during development), which would chain our observers onto themselves and produce
	-- duplicate processing.
	if bStealthTrackerInitialized then return end
	bStealthTrackerInitialized = true

	IS_FGC = checkFGC()

	LOCALIZED_DEXTERITY = Interface.getString(DEXTERITY)
	LOCALIZED_DEXTERITY_LOWER = LOCALIZED_DEXTERITY:lower()
	LOCALIZED_STEALTH = Interface.getString("skill_value_stealth")
	LOCALIZED_STEALTH_ABV = LOCALIZED_STEALTH:sub(1, 1)
	LOCALIZED_STEALTH_LOWER = LOCALIZED_STEALTH:lower()
	USER_ISHOST = (Session and Session.IsHost) or (User and User.isHost and User.isHost()) or false

	-- Only set up the Custom Turn, Combat Reset, Custom Drop, and OOB Message event handlers on the host machine because it has access/permission to all of the necessary data.
	if USER_ISHOST then
        local option_entry_cycler = "option_entry_cycler"
        local option_header = "option_header_STEALTHTRACKER"
        local option_val_none = "option_val_none_STEALTHTRACKER"
        local option_val_off = "option_val_off"
        local option_val_on = "option_val_on"
        local both = "both"
        local standard = "standard"

        OptionsManager.registerOption2(STEALTHTRACKER_ALLOW_OUT_OF, false, option_header, "option_label_STEALTHTRACKER_ALLOW_OUT_OF", option_entry_cycler,
            { baselabel = option_val_none, baseval = NONE, labels = "option_val_turn_STEALTHTRACKER|option_val_turn_and_combat_STEALTHTRACKER", values = "turn|" .. ALL, default = NONE })
        OptionsManager.registerOption2(STEALTHTRACKER_EXPIRE_EFFECT, false, option_header, "option_label_STEALTHTRACKER_EXPIRE_EFFECT", option_entry_cycler,
            { baselabel = "option_val_attack_and_round_STEALTHTRACKER", baseval = ALL, labels = "option_val_attack_STEALTHTRACKER|" .. option_val_none, values = "attack|" .. NONE, default = ALL })
        OptionsManager.registerOption2(STEALTHTRACKER_FACTION_FILTER, false, option_header, "option_label_STEALTHTRACKER_FACTION_FILTER", option_entry_cycler,
            { labels = option_val_off, values = OFF, baselabel = "option_val_on", baseval = ON, default = ON })
        OptionsManager.registerOption2(STEALTHTRACKER_VISIBILITY, false, option_header, "option_label_STEALTHTRACKER_VISIBILITY", option_entry_cycler,
            { baselabel = "option_val_chat_and_effects_STEALTHTRACKER", baseval = ALL, labels = "option_val_effects_STEALTHTRACKER|" .. option_val_none, values = EFFECTS .. "|" .. NONE, default = EFFECTS })
        OptionsManager.registerOption2(STEALTHTRACKER_VERBOSE, false, option_header, "option_label_STEALTHTRACKER_VERBOSE", option_entry_cycler,
            { baselabel = "option_val_standard", baseval = standard, labels = "option_val_max|" .. option_val_off, values = "max|" .. OFF, default = standard })
        OptionsManager.registerOption2(STEALTHTRACKER_AWARE, false, option_header, "option_label_STEALTHTRACKER_AWARE", option_entry_cycler,
            { baselabel = "option_val_both_STEALTHTRACKER", baseval = both, labels = "option_val_none_STEALTHTRACKER|option_val_aware_STEALTHTRACKER|option_val_unaware_STEALTHTRACKER", values = NONE .. "|" .. AWARE .. "|" .. UNAWARE, default = both })
        OptionsManager.registerOption2(STEALTHTRACKER_VISIBLE, false, option_header, "option_label_STEALTHTRACKER_VISIBLE", option_entry_cycler,
            { baselabel = "option_val_hidden_STEALTHTRACKER", baseval = HIDDEN, labels = "option_val_none_STEALTHTRACKER|option_val_visible_STEALTHTRACKER|option_val_both_STEALTHTRACKER", values = NONE .. "|" .. VISIBLE .. "|" .. both, default = HIDDEN })
        OptionsManager.registerOption2(STEALTHTRACKER_INIT_CLEAR, false, option_header, "option_label_STEALTHTRACKER_INIT_CLEAR", option_entry_cycler,
            { labels = option_val_off, values = OFF, baselabel = "option_val_on", baseval = ON, default = ON })
        OptionsManager.registerOption2(STEALTHTRACKER_SHOW_AFTER_STEALTH, false, option_header, "option_label_STEALTHTRACKER_SHOW_AFTER_STEALTH", option_entry_cycler,
            { labels = option_val_off, values = OFF, baselabel = "option_val_on", baseval = ON, default = ON })
        OptionsManager.registerOption2(STEALTHTRACKER_FRAME_STYLE, false, option_header, "option_label_STEALTHTRACKER_FRAME_STYLE", option_entry_cycler,
            { baselabel = option_val_none, baseval = NONE, labels = "option_val_chat_STEALTHTRACKER|option_val_story_STEALTHTRACKER|option_val_whisper_STEALTHTRACKER", values = "chat|story|whisper", default = NONE })
        OptionsManager.registerOption2(STEALTHTRACKER_SHOW_EYE, false, option_header, "option_label_STEALTHTRACKER_SHOW_EYE", option_entry_cycler,
            { labels = option_val_on, values = ON, baselabel = "option_val_off", baseval = OFF, default = OFF })

            CombatManager.setCustomCombatReset(onCombatResetEvent)
		-- Drop onto CT hook for GM to drag a stealth roll or check onto a CT actor for a quick Stealth effect set (works for actors who's turn it isn't).
		-- Note: In modern CoreRPG, CombatDropManager.handleActionDropEvent unconditionally returns true, true,
		-- which prevents CombatDropManager.handleAnyDrop from ever reaching handleLegacyDropEvent / registerLegacyDropCallback.
		-- Wrapping handleAnyDrop ensures CT drops are always observed.
		if CombatDropManager and CombatDropManager.handleAnyDrop then
			local fOriginalHandleAnyDrop = CombatDropManager.handleAnyDrop
			CombatDropManager.handleAnyDrop = function(draginfo, sTargetPath, ...)
				if sTargetPath and sTargetPath ~= "" and draginfo then
					local rSource = ActionsManager.decodeActors(draginfo)
					local rTarget = getActorSafe(sTargetPath)
					onDropEvent(rSource, rTarget, draginfo)
				end
				return fOriginalHandleAnyDrop(draginfo, sTargetPath, ...)
			end
		elseif CombatDropManager and CombatDropManager.registerLegacyDropCallback then
			CombatDropManager.registerLegacyDropCallback(onDropEvent)
		elseif CombatDropManager and CombatDropManager.onLegacyDropEvent then
			local fOriginalLegacyDrop = CombatDropManager.onLegacyDropEvent
			CombatDropManager.onLegacyDropEvent = function(rSource, rTarget, draginfo)
				onDropEvent(rSource, rTarget, draginfo)
				if fOriginalLegacyDrop then
					fOriginalLegacyDrop(rSource, rTarget, draginfo)
				end
			end
		else
			if CombatManager.onDrop ~= onDrop then
				CombatManager_onDrop = CombatManager.onDrop
				CombatManager.onDrop = onDrop
			end
		end

        if CombatManager.requestActivation ~= requestActivation then
            CombatManager_requestActivation = CombatManager.requestActivation
            CombatManager.requestActivation = requestActivation
        end

		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_UPDATESTEALTH, handleUpdateStealth)
		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_ATTACKFROMSTEALTH, handleAttackFromStealth)

		-- Register chat commands for host only.
		Comm.registerSlashHandler("stealth", processChatCommand)
	end

	-- Hook roll initiation so Stealth rolls can be flagged secret before 3D dice are thrown.
	if ActionsManager and ActionsManager.performAction and ActionsManager.performAction ~= onPerformAction then
		ActionsManager_performAction_Original = ActionsManager.performAction
		ActionsManager.performAction = onPerformAction
	end

	-- Hook roll resolution via ActionsManager.
	-- We capture the existing result handler (from ruleset or prior extensions), execute it first,
	-- and then execute our observer (onRollSkill / onRollAttack) to process Stealth effects and chat.
	local aRollTypes = { "skill", "attack" }
	for _, sType in ipairs(aRollTypes) do
		local bAttack = (sType == "attack")
		local fObserver = bAttack and onRollAttack or onRollSkill
		local fOriginal = getResultHandlerSafe(sType)
		while fOriginal and aOwnResultWrappers[fOriginal] and aOwnResultWrappers[fOriginal] ~= true do
			fOriginal = aOwnResultWrappers[fOriginal]
		end
		if fOriginal and aOwnResultWrappers[fOriginal] == true then
			fOriginal = nil
		end
		local fWrapper = function(rSource, rTarget, rRoll)
			if not bAttack then
				onInitiateSkill(rSource, rTarget, rRoll)
			end
			if fOriginal then
				fOriginal(rSource, rTarget, rRoll)
			end
			local bStatus, sError = pcall(fObserver, rSource, rTarget, rRoll)
			if not bStatus and Debug and Debug.console then
				Debug.console("StealthTracker observer error: " .. tostring(sError))
			end
		end
		aOwnResultWrappers[fWrapper] = fOriginal or true
		ActionsManager.registerResultHandler(sType, fWrapper)
	end

	-- Compatibility with Generic Actions extension so that Hide action is treated as Stealth skill check.
	if ActionGeneral then
		ActionsManager.registerPostRollHandler(GENACTROLL, onGenericActionPostRoll)
	end
end

-- Alphebetical list of functions below (onInit() above was an exception)

function booleanToNumber(bValue)
	return bValue and 1 or 0
end

function checkAllowOutOfCombat()
	return OptionsManager.isOption(STEALTHTRACKER_ALLOW_OUT_OF, ALL)
end

function checkAllowOutOfTurn()
	return OptionsManager.isOption(STEALTHTRACKER_ALLOW_OUT_OF, TURN) or
		   checkAllowOutOfCombat()
end

function getActiveDuplicateCTNodePath(sCTNode)
	local nodeCT = ActorManager.getCTNode(sCTNode)
	local nodeActiveCT = CombatManager.getActiveCT()
	local sNodePath = getNodePathSafe(nodeCT)
	local sActivePath = getNodePathSafe(nodeActiveCT)
	if sNodePath and sActivePath and sNodePath ~= sActivePath then
		local nodeCreature = ActorManager.getCreatureNode(nodeCT)
		local nodeActiveCreature = ActorManager.getCreatureNode(nodeActiveCT)
		local sCreaturePath = getNodePathSafe(nodeCreature)
		local sActiveCreaturePath = getNodePathSafe(nodeActiveCreature)
		if sCreaturePath and sCreaturePath == sActiveCreaturePath then
			return sActivePath
		end
	end
	return sCTNode
end

function resolveTargetDuplicateCTNode(rSource, rTarget)
	if not rTarget or not rSource then return rTarget end
	
	local nodeTargetCT = ActorManager.getCTNode(rTarget)
	if not nodeTargetCT then return rTarget end
	
	local sTargetName = ActorManager.getDisplayName(rTarget)
	if sTargetName == "" then return rTarget end
	
	-- 1. Check if the attacker has a target selected with the same name
	if TargetingManager and TargetingManager.getFullTargets then
		local aTargets = TargetingManager.getFullTargets(rSource)
		for _, rT in ipairs(aTargets or {}) do
			local nodeTCT = ActorManager.getCTNode(rT)
			if nodeTCT then
				local sTName = ActorManager.getDisplayName(rT)
				if StringManager.trim(sTName) == StringManager.trim(sTargetName) then
					return rT
				end
			end
		end
	end
	
	-- 2. Fallback for drops: Find if any CT entry with the same name has a Stealth effect
	local nodeHighestStealthCT = nil
	local nHighestStealth = -1
	
	if CombatManager and CombatManager.getSortedCombatantList then
		local lCombatTrackerActors = CombatManager.getSortedCombatantList()
		for _, nodeCT in ipairs(lCombatTrackerActors or {}) do
			local sCTName = ActorManager.getDisplayName(nodeCT)
			if sCTName == sTargetName then
				local nStealth = getStealthNumberFromEffects(nodeCT)
				if nStealth and nStealth > nHighestStealth then
					nHighestStealth = nStealth
					nodeHighestStealthCT = nodeCT
				end
			end
		end
	end
	
	local sHighestPath = getNodePathSafe(nodeHighestStealthCT)
	local sTargetCTPath = getNodePathSafe(nodeTargetCT)
	if sHighestPath and sTargetCTPath and sHighestPath ~= sTargetCTPath then
		local rNewTarget = ActorManager.resolveActor(nodeHighestStealthCT)
		if rNewTarget then
			return rNewTarget
		end
	end
	
	return rTarget
end

function checkAndDisplayAllowOutOfCombatAndTurnChecks(vActor)
	if checkAndDisplayCTInactiveAndOutsideOfCombatStealthDisallowed() then return false end

	local nodeCT = ActorManager.getCTNode(vActor)
	local nodeActiveCT = CombatManager.getActiveCT()
	local sNodeCTPath = getNodePathSafe(nodeCT) or getNodePathSafe(vActor)
	local sActiveCTPath = getNodePathSafe(nodeActiveCT)
	local bAllowOutOfTurn = checkAllowOutOfTurn()

	if (not sActiveCTPath or sActiveCTPath ~= sNodeCTPath) and not bAllowOutOfTurn then
		if checkVerbosityMax() then
			displayChatMessage(string.format(ST_STEALTH_DISABLED_OUT_OF_FORMAT, TURN), SECRET)
		end

		return false
	end

	return true
end

function checkAndDisplayCTInactiveAndOutsideOfCombatStealthDisallowed()
	if not CombatManager.getActiveCT() and not checkAllowOutOfCombat() then
		if checkVerbosityMax() then
			displayChatMessage(string.format(ST_STEALTH_DISABLED_OUT_OF_FORMAT, "combat"), SECRET)
		end

		return true
	end

	return false
end

function checkExpireActionAndRound()
	return OptionsManager.isOption(STEALTHTRACKER_EXPIRE_EFFECT, ALL)
end

function checkExpireNone()
	return OptionsManager.isOption(STEALTHTRACKER_EXPIRE_EFFECT, NONE)
end

function checkFactionFilter()
	return OptionsManager.isOption(STEALTHTRACKER_FACTION_FILTER, ON)
end
function checkFGC()
    if UtilityManager and UtilityManager.isClientFGU then
        return not UtilityManager.isClientFGU()
    end
    if Session and Session.VersionMajor then
        return Session.VersionMajor < 4
    end
    if Interface and Interface.getVersion then
        local sVersion = tostring(Interface.getVersion() or "")
        local sMajor = sVersion:match("^(%d+)")
        local nMajor = tonumber(sMajor) or 0
        return nMajor < 4
    end
    return false
end
function checkShowEye()
    return OptionsManager.getOption(STEALTHTRACKER_SHOW_EYE) == ON
end

function checkVerbosityMax()
	return OptionsManager.getOption(STEALTHTRACKER_VERBOSE) == "max"
end

function checkVerbosityOff()
	return OptionsManager.getOption(STEALTHTRACKER_VERBOSE) == OFF
end

-- Deletes all of the stealth effects for a CT node (no expiration warning because this is cleanup and not effect usage causing the deletion).
function deleteAllStealthEffects(nodeCT)
	if not nodeCT then return end

	for _, nodeEffect in pairs(DB.getChildren(nodeCT, EFFECTS)) do
		if getStealthValueFromEffectNode(nodeEffect) then
			if DB and DB.deleteNode then
				DB.deleteNode(nodeEffect)
			elseif nodeEffect.delete then
				nodeEffect.delete()
			end
		end
	end
end

-- Puts a message in chat that is broadcast to everyone attached to the host (including the host) if bSecret is true, otherwise local only.
function displayChatMessage(sFormattedText, bSecret)
	if sFormattedText == nil then return end

	-- Framed chat modes render via a FormattedText control that parses the text as XML - escape
	-- any raw "<" so message text can never break it ("&lt;" renders as "<").
	local sSafeText = sFormattedText:gsub("<", "&lt;")
	local msg = {font = "msgfont", icon = "stealth_icon", secret = checkShowEye(), text = sSafeText}
	-- Per the Comm refdoc, mode should be "set only if you want to specify a chat mode".
	local sMode = getMode()
	if sMode ~= "" then
		msg.mode = sMode
	end
	-- deliverChatMessage() is a broadcast mechanism, addChatMessage() is local only.
	if bSecret then
		Comm.addChatMessage(msg)
	else
		Comm.deliverChatMessage(msg)
	end
end

function displayDebilitatingConditionChatMessage(vActor, sCondition, bForce)
	if not bForce and checkVerbosityOff() then return end

	local sText = string.format("%s is %s, skipping StealthTracker processing.",
								getActorDisplayNameSafe(vActor),
								sCondition)
	displayChatMessage(sText, SECRET)
end

-- Logic to process an attack from stealth (for checking if enemies could have been attacked with advantage, etc).
function displayProcessAttackFromStealth(rSource, rTarget)
	if not rSource then return end

	local rSourceActor = getActorSafe(rSource)
	if rSourceActor then
		rSource = rSourceActor
	end

	-- Ensure rSource.sCTNode is populated if possible
	if not rSource.sCTNode or rSource.sCTNode == "" then
		local sCTNode = ActorManager.getCTNodeName(rSource)
		if sCTNode and sCTNode ~= "" then
			rSource.sCTNode = sCTNode
		elseif rSource.sCreatureNode and rSource.sCreatureNode ~= "" and CombatManager and CombatManager.getCTFromNode then
			local nodeSCT = CombatManager.getCTFromNode(rSource.sCreatureNode)
			if nodeSCT then
				rSource.sCTNode = getNodePathSafe(nodeSCT) or ""
			end
		end
	end

	-- if no source or no CT node then exit, skipping StealthTracker processing.
	if not rSource or not rSource.sCTNode or rSource.sCTNode == "" then return end

	if rTarget then
		local rTargetActor = getActorSafe(rTarget)
		if rTargetActor then
			rTarget = rTargetActor
		end
		if not rTarget.sCTNode or rTarget.sCTNode == "" then
			local sTCTNode = ActorManager.getCTNodeName(rTarget)
			if sTCTNode and sTCTNode ~= "" then
				rTarget.sCTNode = sTCTNode
			elseif rTarget.sCreatureNode and rTarget.sCreatureNode ~= "" and CombatManager and CombatManager.getCTFromNode then
				local nodeTCT = CombatManager.getCTFromNode(rTarget.sCreatureNode)
				if nodeTCT then
					rTarget.sCTNode = getNodePathSafe(nodeTCT) or ""
				end
			end
		end
		-- Redirect rTarget to correct duplicate if applicable
		rTarget = resolveTargetDuplicateCTNode(rSource, rTarget)
	end

	-- Extract the stealth number from the source, if available.  It's used later in this function at a couple spots.
	local nodeSourceCT = ActorManager.getCTNode(rSource)
	if not nodeSourceCT then return end

	if not USER_ISHOST then
		-- For clients notify of an action from stealth and then exit.  Host handler will pick up message and run code after this block.
		local sTargetCTNode = (rTarget and rTarget.sCTNode) or ""
		notifyAttackFromStealth(rSource.sCTNode, sTargetCTNode)
		return
	end

	-- HOST ONLY PROCESSING STARTS HERE ----------------------------------------------------------------------------------------------------------
	if checkAndDisplayCTInactiveAndOutsideOfCombatStealthDisallowed() then return end

	local sCondition = getActorDebilitatingCondition(nodeSourceCT)
	if sCondition then
		displayDebilitatingConditionChatMessage(nodeSourceCT, sCondition)
		return
	end

	local aOutput = {}
	if rTarget then
		local rHiddenTarget = isTargetHiddenFromSource(rSource, rTarget)
		if rHiddenTarget and rHiddenTarget.hidden then
			local sPPDisplay = getFormattedPPString(rHiddenTarget.sourcePP, rHiddenTarget.sourcePPMod or 0)
			local sMsgText = string.format("Target hidden. Attack possible? (%s %s: %d, %s PP: %s).",
											getActorDisplayNameSafe(rTarget),
											LOCALIZED_STEALTH_ABV,
											rHiddenTarget.stealth,
											getActorDisplayNameSafe(rSource),
											sPPDisplay)
			table.insert(aOutput, sMsgText)
		end

		local nStealthSource = getStealthNumberFromEffects(nodeSourceCT)
		-- If the attacker/source was hiding, then check to see if the target can see the attack coming by comparing that stealth to the target's PP.
		if nStealthSource then
			getFormattedPerformAttackFromStealth(rSource, rTarget, nStealthSource, aOutput)
		end
	else
        -- Check them all
		if checkVerbosityMax() then
			insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "No attack target!")
		end

		getFormattedStealthDataFromCT(nodeSourceCT, aOutput)
	end

	expireStealthEffectOnCTNode(rSource, aOutput)
	displayTableIfNonEmpty(aOutput)
end

-- This function executes on clients.
function displayProcessStealthUpdateForSkillHandlers(rSource, rRoll)
	-- To alter the creature effect, the source must be in the CT, combat must be going (there must be an active CT node), the first dice must be present in the roll, and the dice roller must either the DM or the actor who is active in the CT.
	if rSource and rSource.sCTNode and rSource.sCTNode ~= "" and ActionsManager.doesRollHaveDice(rRoll) then
        -- Explicitly decode advantage/disadvantage using 5E-specific managers if not already decoded (e.g. by Generic Actions or ruleset).
        if not isRollAdvantageDecoded(rRoll) then
            if ActionD20 and ActionD20.decodeAdvantage then
                ActionD20.decodeAdvantage(rRoll)
                rRoll.bAdvantageDecoded = true
            elseif ActionsManager2 and ActionsManager2.decodeAdvantage then
                ActionsManager2.decodeAdvantage(rRoll)
                rRoll.bAdvantageDecoded = true
            end
        end

		-- Calculate the stealth roll so that it's available to put in the creature effects.
		local nStealthTotal = ActionsManager.total(rRoll)
		local sTargetCTNode = getActiveDuplicateCTNodePath(rSource.sCTNode)
		local bSecret = (rRoll.bSecret == true or rRoll.bSecret == 1 or rRoll.bSecret == "1"
						 or rRoll.bTower == true or rRoll.bTower == 1 or rRoll.bTower == "1")

		-- If the source of the roll is a npc sheet shared to a player, notify the host to update the stealth value.
		if USER_ISHOST then
			-- The CT node and the character sheet node are different nodes.  Updating the name on the CT node only updates the CT and not their character sheet value.
			local bAllow = checkAndDisplayAllowOutOfCombatAndTurnChecks(sTargetCTNode)
			if bAllow then
				setNodeWithStealthValue(sTargetCTNode, nStealthTotal, bSecret)
                -- Display the stealth information now that the Stealth roll has been made so the DM can take advantage of the info if it all happens on the same turn (i.e. hide, then attack).
                if OptionsManager.getOption(STEALTHTRACKER_SHOW_AFTER_STEALTH) == ON then
                    local nodeCT = ActorManager.getCTNode(sTargetCTNode)
                    displayStealthCheckInformationWithConditionAndVerboseChecks(nodeCT, FORCE_DISPLAY)
                end
			end
		else
			notifyUpdateStealth(sTargetCTNode, nStealthTotal, bSecret)
		end
	end
end

function displayStealthCheckInformationWithConditionAndVerboseChecks(nodeCT, bForce)
	-- Check to make sure the CT actor is conscious.  Unconscious/stunned/whatever actors should not be assessed.
	local sCondition = getActorDebilitatingCondition(nodeCT)
	if sCondition then
		displayDebilitatingConditionChatMessage(nodeCT, sCondition, bForce)
		return
	end

	local aOutput = {}
	getFormattedStealthDataFromCT(nodeCT, aOutput)
	displayTableIfNonEmpty(aOutput, bForce)
end

function displayTableIfNonEmpty(aTable, bForce)
	if not bForce and checkVerbosityOff() then return end

	aTable = validateTableOrNew(aTable)
	if #aTable > 0 then
		local sDisplay = table.concat(aTable, "\r")
		displayChatMessage(sDisplay, SECRET)
	end
end

function displayTowerRoll()
	if checkVerbosityOff() then return end

	displayChatMessage("An attack was rolled in the tower.  Attacks should be rolled in the open for proper StealthTracker processing.", USER_ISHOST)
end

-- Function to check if the target perceives the attacker under stealth, returning true if so and false if not.
function doesTargetPerceiveAttackerFromStealth(nAttackerStealth, rTarget, rAttacker)
	if nAttackerStealth == nil or not rTarget then return false end

	local nPPTarget = getPassivePerceptionNumber(rTarget)
	if nPPTarget == nil then return false end

	if rAttacker then
		nPPTarget = nPPTarget + getStealthEffectModifier(rAttacker)
	end

	return nPPTarget >= nAttackerStealth
end

function ensureStealthSkillExistsOnNpc(nodeCT)
	if not nodeCT then return end

	local rCurrentActor = getActorSafe(nodeCT)
	if not rCurrentActor or not isNpc(rCurrentActor) then return end

	-- Consider the dex mod in any Stealth skill added to NPC sheet.  Bonus is always there, so chain.
	local nDexMod = getAbilityBonusSafe(nodeCT, DEXTERITY)
	local sStealthWithMod = LOCALIZED_STEALTH .. " "
	if nDexMod >= 0 then
		sStealthWithMod = sStealthWithMod .. "+"
	end

	sStealthWithMod = sStealthWithMod .. nDexMod -- Ex: Stealth +0 or Stealth -2
	local sSkills = DB.getValue(nodeCT, "skills", "")
	if sSkills == "" then
		DB.setValue(nodeCT, "skills", "string", sStealthWithMod)
	elseif not sSkills:lower():match(LOCALIZED_STEALTH_LOWER .. "%s+[+-]?%d") then
		-- Prepend the zero Stealth bonus to the skills (didn't bother sorting which would require tokenization, table sort, and joining).
		local sNewSkillsValue = sStealthWithMod .. ", " .. sSkills
		-- Trim off any trailing comma followed by zero or more whitespace.
		DB.setValue(nodeCT, "skills", "string", sNewSkillsValue:gsub("^%s*(.-),%s*$", "%1"))
	end
end

function expireStealthEffectOnCTNode(rActor, aOutput)
	if not rActor then return end

	local nodeCT = ActorManager.getCTNode(rActor)
	if not nodeCT then return end

	local nodeLastEffectWithStealth
	-- Walk the effects in order so that the last one added is taken in case they are stacked.
	for _, nodeEffect in pairs(DB.getChildren(nodeCT, EFFECTS)) do
		local sExtractedStealth = getStealthValueFromEffectNode(nodeEffect)
		if sExtractedStealth then
			nodeLastEffectWithStealth = nodeEffect
		end
	end

	-- If a stealth node was found walking the list, expire the effect.
	if nodeLastEffectWithStealth then
		if checkExpireNone() then
			if checkVerbosityMax() then
				local sText = string.format("%s took an attack from stealth that should expire the effect.",
											getActorDisplayNameSafe(rActor))
				insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
			end
		else
			if EffectManager and EffectManager.expireEffect then
				EffectManager.expireEffect(nodeCT, nodeLastEffectWithStealth, 0)
			elseif DB and DB.deleteNode then
				DB.deleteNode(nodeLastEffectWithStealth)
			elseif nodeLastEffectWithStealth.delete then
				nodeLastEffectWithStealth.delete()
			end
		end
	end
end

function getActorDebilitatingCondition(vActor)
	local rActor = getActorSafe(vActor)
	if not rActor then return nil end

	local aConditions = { -- prioritized
		"unconscious",
		"incapacitated",
		"stunned",
		"paralyzed",
		"petrified",
		"stable" -- FG, not 5e
	}

	for _, sCondition in ipairs(aConditions) do
		if hasEffectSafe(rActor, sCondition) then return sCondition end
	end

	return nil
end

function getActorDisplayNameSafe(vActor)
	if not vActor then return UNIDENTIFIED end
	local nodeCT = ActorManager.getCTNode(vActor)
	local rActor = getActorSafe(vActor) or vActor
	local sDisplayName = ActorManager.getDisplayName(rActor)
	if isBlankSafe(sDisplayName) or (nodeCT and isUnidentifiedNpc(nodeCT)) then
		return getUnidentifiedName(nodeCT or rActor)
	end
	return sDisplayName
end

-- Fallback passive Perception used only when it can't be read from the sheet (PC) or the NPC 'senses' field.
-- Per 5e RAW (both 2014 and 2024), passive Perception = 10 + Wisdom (Perception) check modifier, where
-- proficiency is only included if the creature is actually proficient in Perception.  A bare NPC stat block
-- that reaches this fallback has no listed Perception proficiency, so we use 10 + Wis mod and avoid the
-- previous behavior of unconditionally adding the full proficiency bonus (which over-stated PP for
-- non-proficient creatures and made hidden actors easier to detect).
function getDefaultPassivePerception(nodeCreature)
    return 10 + getAbilityBonusSafe(nodeCreature, "wisdom")
end

-- Function that walks the CT nodes and deletes the stealth effects from them.
function getFormattedAndClearAllStealthTrackerDataFromCTIfAllowed(aOutput, bForce)
	aOutput = validateTableOrNew(aOutput)
	if checkAllowOutOfCombat() and not bForce then
		insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "Out of combat Stealth is allowed in the options. Leaving CT stealth effects after reset.")
		return
	end

	-- Walk the CT resetting all names.
	for _, nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
		deleteAllStealthEffects(nodeCT)
	end

	insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "All Stealth effects deleted on combat reset.")
end

-- Formats the PP string to include the modifier if it exists (e.g. "10 [15 - 5]" or just "10")
function getFormattedPPString(nPPEffective, nPPMod)
	if not nPPEffective then return "" end
	if not nPPMod or nPPMod == 0 then
		return string.format("%d", nPPEffective)
	end
	local nBase = nPPEffective - nPPMod
	if nPPMod > 0 then
		return string.format("%d [%d + %d]", nPPEffective, nBase, nPPMod)
	else
		return string.format("%d [%d - %d]", nPPEffective, nBase, math.abs(nPPMod))
	end
end

-- Function to do the 'attack from stealth' comparison where the attacker could have advantage if the target doesn't perceive the attacker (chat msg displayed).
-- This is called from the host only.
function getFormattedPerformAttackFromStealth(rSource, rTarget, nStealthSource, aOutput)
	if not rSource or not rTarget or nStealthSource == nil then return end

	aOutput = validateTableOrNew(aOutput)
	local sMsgText
	local nPPEffective, nPPMod = getPassivePerceptionWithModifier(rTarget, rSource)
	local sPPDisplay = getFormattedPPString(nPPEffective, nPPMod)
	local sStats = string.format("(%s %s: %d, %s PP: %s)",
								 getActorDisplayNameSafe(rSource),
								 LOCALIZED_STEALTH_ABV,
								 nStealthSource,
								 getActorDisplayNameSafe(rTarget),
								 sPPDisplay)
	if not doesTargetPerceiveAttackerFromStealth(nStealthSource, rTarget, rSource) then
		-- Warn the chat that the attacker is hidden from the target in case they can take advantage on the roll (i.e. roll the attack again).
		sMsgText = string.format("Attacker is hidden. Attack at advantage? %s", sStats)
	elseif checkVerbosityMax() then
		-- Target sees the attack coming.  Build appropriate message.
		sMsgText = string.format("Attacker not hidden. %s", sStats)
	else
		sMsgText = nil
	end

	if sMsgText then
		insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sMsgText)
	end
end

function getFormattedStealthDataFromCT(nodeCTSource, aOutput)
    local rStealthData = {}
    rStealthData.visible = {} -- visible to current actor
    rStealthData.hidden = {} -- hidden from current actor
    rStealthData.aware = {} -- aware of the current actor
    rStealthData.unaware = {} -- unaware of the current actor

    if not nodeCTSource then return rStealthData end

	local rCurrentActor = getActorSafe(nodeCTSource)
	if not rCurrentActor then return rStealthData end

    local sCTSourceDisplayName = getActorDisplayNameSafe(nodeCTSource)

    local nStealthSource = getStealthNumberFromEffects(nodeCTSource)
	-- Loop through the CT, getSortedCombatantList() returns the list ordered as-is in CT (sorted by the CombatManager.sortfuncDnD sort function loaded by the 5e ruleset) and is never nil
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	for _, nodeCT in ipairs(lCombatTrackerActors) do
        if isValidCTNode(nodeCT) then  -- hasValidType(nodeCT) or isFriend(nodeCT)
            -- Two checks will be needed each iteration.  One for visible/hidden and the other for aware/unaware.
            local rIterationActor = getActorSafe(nodeCT)
            if rIterationActor then
                local sIterationActorDisplayName = getActorDisplayNameSafe(nodeCT)

                local sDebilitatingCondition = getActorDebilitatingCondition(rIterationActor)
                if rCurrentActor.sCTNode ~= rIterationActor.sCTNode and  -- Current actor doesn't equal iteration actor (no need to report on the actors own visibility!).
                   (not checkFactionFilter() or isDifferentFaction(nodeCTSource, nodeCT)) then  -- friendly faction filter
                    local rHiddenTarget = isTargetHiddenFromSource(rCurrentActor, rIterationActor)
                    if rHiddenTarget and sDebilitatingCondition == nil then
                        local sText = string.format("%s - %s: %d", -- ex: ActorName - Stealth: 8
                                                    sIterationActorDisplayName,
                                                    LOCALIZED_STEALTH,
                                                    rHiddenTarget.stealth)
                        if rHiddenTarget.sourcePPMod and rHiddenTarget.sourcePPMod ~= 0 then
                            local sPPDisplay = getFormattedPPString(rHiddenTarget.sourcePP, rHiddenTarget.sourcePPMod)
                            sText = sText .. string.format(" (PP: %s)", sPPDisplay)
                        end
                        if rHiddenTarget.hidden then
                            table.insert(rStealthData.hidden, sText)
                        else
                            table.insert(rStealthData.visible, sText)
                        end
                    end

                    -- Check the aware/unaware, same text in each that will be rolled up in the output section below.
                    if nStealthSource ~= nil then
                        local sText = string.format("%s", sIterationActorDisplayName)
                        local nPPEffective, nPPMod = getPassivePerceptionWithModifier(rIterationActor, rCurrentActor)
                        local sPPDisplay = getFormattedPPString(nPPEffective, nPPMod)
                        local sPPText = string.format(" - PP: %s", sPPDisplay)
                        local sConditionFormat = " - Condition: %s"
                        if doesTargetPerceiveAttackerFromStealth(nStealthSource, rIterationActor, rCurrentActor) then
                            if sDebilitatingCondition == nil then
                                table.insert(rStealthData.aware, sText .. sPPText)
                            else
                                local sConditionText = string.format(sConditionFormat, sDebilitatingCondition)
                                table.insert(rStealthData.unaware, sText .. sPPText .. sConditionText)
                            end
                        else
                            if sDebilitatingCondition == nil then
                                table.insert(rStealthData.unaware, sText .. sPPText)
                            else
                                local sConditionText = string.format(sConditionFormat, sDebilitatingCondition)
                                table.insert(rStealthData.unaware, sText .. sConditionText)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Data consolidation section for output table
    aOutput = validateTableOrNew(aOutput)
    if OptionsManager.getOption(STEALTHTRACKER_VISIBLE) ~= NONE then
        if OptionsManager.getOption(STEALTHTRACKER_VISIBLE) ~= VISIBLE then
            if #rStealthData.hidden > 0 then
                local sText = string.format("%s (PP: %d) does not perceive:\r%s",
                                            sCTSourceDisplayName,
                                            getPassivePerceptionNumber(rCurrentActor),
                                            table.concat(rStealthData.hidden, "\r"))
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
            else
                if checkVerbosityMax() then
                    local sText = string.format("There are no actors hidden from %s.",
                                                sCTSourceDisplayName)
                    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
                end
            end
        end

        if OptionsManager.getOption(STEALTHTRACKER_VISIBLE) ~= HIDDEN then
            if #rStealthData.visible > 0 then
                local sText = string.format("%s (PP: %d) sees:\r%s",
                                            sCTSourceDisplayName,
                                            getPassivePerceptionNumber(rCurrentActor),
                                            table.concat(rStealthData.visible, "\r"))
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
            else
                if checkVerbosityMax() then
                    local sText = string.format("There are no hiding actors visible to %s.",
                                                sCTSourceDisplayName)
                    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
                end
            end
        end
    end

    -- The aware/unaware summary only makes sense when the source has a stealth value; guarding here also
    -- ensures nStealthSource is non-nil for the %d formatting below (rStealthData.aware/unaware are only
    -- populated under that same condition during the CT walk above).
    if nStealthSource ~= nil and OptionsManager.getOption(STEALTHTRACKER_AWARE) ~= NONE then
        if OptionsManager.getOption(STEALTHTRACKER_AWARE) ~= UNAWARE then
            if #rStealthData.aware > 0 then
                -- Now, let's display a summary message and append the output strings from above appended to the end.
                local sText = string.format("%s (%s: %d) is seen by:\r%s",
                                            sCTSourceDisplayName,
                                            LOCALIZED_STEALTH,
                                            nStealthSource,
                                            table.concat(rStealthData.aware, "\r"))
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
            else
                if checkVerbosityMax() then
                    local sText = string.format("There are no actors that can see %s.",
                                                sCTSourceDisplayName)
                    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
                end
            end
        end

        if OptionsManager.getOption(STEALTHTRACKER_AWARE) ~= AWARE then
            if #rStealthData.unaware > 0 then
                -- Now, let's display a summary message and append the output strings from above appended to the end.
                local sText = string.format("%s (%s: %d) is hidden from:\r%s",
                                            sCTSourceDisplayName,
                                            LOCALIZED_STEALTH,
                                            nStealthSource,
                                            table.concat(rStealthData.unaware, "\r"))
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
            else
                if checkVerbosityMax() then
                    local sText = string.format("There are no actors unaware of %s.",
                                                sCTSourceDisplayName)
                    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
                end
            end
        end
    end

    return rStealthData
end

function getMode()
    local sFrameStyle = OptionsManager.getOption(STEALTHTRACKER_FRAME_STYLE)
    if sFrameStyle == NONE then
        sFrameStyle = ""
    end

    return sFrameStyle
end

-- This gets the Passive Perception number from the character sheet for pcs and ct node for npc.
-- This function can return nil.
function getPassivePerceptionNumber(vActor)
	local nodeCreature = ActorManager.getCreatureNode(vActor)
	if not nodeCreature then return 10 end

	-- The perception is calculated from different sheets for pc vs npc.
	local nPP
	if ActorManager.isPC(vActor) then
		-- For a PC it's the perception child node.
		-- The perception value is always populated and always a number type.
		nPP = DB.getValue(nodeCreature, "perception")
	elseif isNpc(vActor) then
		-- Limitation: NPC must have 'passive Perception X' in the 'senses' field, otherwise, 10+wis is used.
		nPP = tonumber(string.match(DB.getText(nodeCreature, "senses", ""):lower(), "passive%s+perception%s+(%-?%d+)"))
	end

	-- Calculation of passive perception from the wisdom modifier is same for pc/npc and should be used as a last resort (for PCs/charsheet, it should use Perception Prof/Expertise if it's there).
	-- Lua note: When used as control expression, the only false values in Lua are false and nil. Everything else is evaluated as true value (i.e. 0 is a true value because a value is present).
	if nPP == nil then
		nPP = getDefaultPassivePerception(nodeCreature)
	end

	local rActor = getActorSafe(vActor)
    return modifyPassivePerceptionForActorEffects(rActor, nPP)
end

function getAdvDisadvForPerception(rActor)
    local bADV, bDIS = false, false
    if hasEffectSafe(rActor, "ADVSKILL") then
        bADV = true
    elseif #(getEffectsByTypeSafe(rActor, "ADVSKILL", A_SKILL_FILTER)) > 0 then
        bADV = true
    elseif hasEffectSafe(rActor, "ADVCHK") then
        bADV = true
    elseif #(getEffectsByTypeSafe(rActor, "ADVCHK", A_CHECK_FILTER)) > 0 then
        bADV = true
    end
    if hasEffectSafe(rActor, "DISSKILL") then
        bDIS = true
    elseif #(getEffectsByTypeSafe(rActor, "DISSKILL", A_SKILL_FILTER)) > 0 then
        bDIS = true
    elseif hasEffectSafe(rActor, "DISCHK") then
        bDIS = true
    elseif #(getEffectsByTypeSafe(rActor, "DISCHK", A_CHECK_FILTER)) > 0 then
        bDIS = true
    end

    -- if EffectManager5E.hasEffectCondition(rActor, "Frightened") then
    --     bDIS = true
    -- end

    -- Get ability modifiers
    local aAddDice, nAddMod, _ = getEffectsBonusSafe(rActor, {"CHECK"}, false, A_CHECK_FILTER)
    nAddMod = nAddMod or 0
    local aSkillAddDice, nSkillAddMod, nSkillEffectCount = getEffectsBonusSafe(rActor, {"SKILL"}, false, A_SKILL_FILTER)
    if (nSkillEffectCount and nSkillEffectCount > 0) then
        for _,v in ipairs(aSkillAddDice or {}) do
            table.insert(aAddDice, v)
        end
        nAddMod = nAddMod + (nSkillAddMod or 0);
    end

    -- Get ability modifiers
    local nBonusStat, nBonusEffects = getAbilityEffectsBonusSafe(rActor, "wisdom")
    if (nBonusEffects and nBonusEffects > 0) then
        nAddMod = nAddMod + (nBonusStat or 0)
    end

    -- Exhaustion handling, presence-driven and FGC/FGU aware (we never interpret the effect's numeric value,
    -- whose meaning differs by edition).  FGC only ever runs the 2014 ruleset, where exhaustion imposes
    -- disadvantage on ability checks; FG resolves that at roll time and emits no detectable DIS* effect for
    -- passive computation, so on FGC we set the disadvantage flag ourselves when any EXHAUSTION effect is
    -- present.  On FGU the loaded ruleset may be 2014 or 2024 (2024 replaces disadvantage with a flat
    -- -2/level penalty that arrives through the CHECK channel summed above); rather than guess the edition we
    -- defer to whatever that ruleset surfaces through the effect channels and do not assert disadvantage here,
    -- which avoids double-counting the 2024 penalty.
    -- In 5E manager_effect_5E.lua, getEffectsBonus(rActor, {"EXHAUSTION"}, true) returns (nTotalMod, nEffectCount).
    if IS_FGC or checkFGC() then
        local _, nExhaustCount = getEffectsBonusSafe(rActor, {"EXHAUSTION"}, true)
        if (nExhaustCount and nExhaustCount > 0) or hasEffectSafe(rActor, "EXHAUSTION") then
            bDIS = true
        end
    end


    return bADV, bDIS, nAddMod
end

-- Returns the observer's effective Passive Perception and any modifier caused by stealth-related effects on the subject (e.g. Cloak of Elvenkind).
function getPassivePerceptionWithModifier(rObserver, rSubject)
    local nPP = getPassivePerceptionNumber(rObserver)
    local nMod = getStealthEffectModifier(rSubject)
    if nPP == nil then return nil, nMod end
    return nPP + nMod, nMod
end

-- Sums any Passive Perception modifiers imposed on observers by effects on the hiding actor (defined in STEALTH_EFFECT_MODIFIERS).
function getStealthEffectModifier(vActor)
    local nMod = 0
    local rActor = getActorSafe(vActor)
    if not rActor or not STEALTH_EFFECT_MODIFIERS then return nMod end

    for sEffectName, nEffectMod in pairs(STEALTH_EFFECT_MODIFIERS) do
        if hasEffectSafe(rActor, sEffectName) then
            nMod = nMod + nEffectMod
        end
    end

    return nMod
end


-- Function that walks the effects for a given CT node and extracts the last 'Stealth: X' effect stealth value.
function getStealthNumberFromEffects(nodeCT)
	if not nodeCT then return nil end

	local nStealth
	local aEffects = DB.getChildren(nodeCT, EFFECTS)

	-- Walk the effects in order so that the last one added is taken in case they are stacked.  If a duplicate Stealth effect is found, remove subsequent ones.
	for _, nodeEffect in pairs(aEffects) do
		local sExtractedStealth = getStealthValueFromEffectNode(nodeEffect)
		if sExtractedStealth then
			nStealth = tonumber(sExtractedStealth)
		end
	end

	return nStealth
end

-- Used to get the string representation of the stealth value from an effect node.
function getStealthValueFromEffectNode(nodeEffect)
	if not nodeEffect then return end

	local sEffectLabel = DB.getValue(nodeEffect, "label", ""):lower()
	local sExtractedStealth

	-- Let's break that effect up into it's components (i.e. tokenize on ;)
	local aEffectComponents = EffectManager.parseEffect(sEffectLabel)

	-- Take the last Stealth value found, in case it was manually entered and accidentally duplicated (iterate through all of the components).
	local pattern = "^%s*" .. LOCALIZED_STEALTH_LOWER .. ":%s*(%-?%d+)%s*$"
	for _, component in ipairs(aEffectComponents) do
		-- First, strip leading/trailing whitespace
		local sCleanComponent = component:match("^%s*(.-)%s*$") or component
		-- Then strip outer parentheses if present (e.g. from GM-only display label or manual entry)
		sCleanComponent = sCleanComponent:match("^%((.-)%)$") or sCleanComponent
		-- Also strip an unmatched leading parenthesis if FGU split a GM-only effect with semicolons
		sCleanComponent = sCleanComponent:match("^%((.*)$") or sCleanComponent
		-- Also strip an unmatched trailing parenthesis
		sCleanComponent = sCleanComponent:match("^(.-)%)$") or sCleanComponent

		local sMatch = string.match(sCleanComponent, pattern)
		if sMatch then
			sExtractedStealth = sMatch
		end
	end

	return sExtractedStealth
end

function getUnidentifiedName(nodeRecord)
    local unidentifiedName = DB.getValue(nodeRecord, "nonid_name", UNIDENTIFIED)
    if isBlankSafe(unidentifiedName) then
        unidentifiedName = UNIDENTIFIED
    end

    return unidentifiedName
end

-- Handler for the message to do an attack from a position of stealth.
function handleAttackFromStealth(msgOOB)
	displayProcessAttackFromStealth(getActorSafe(msgOOB.sSourceCTNode), getActorSafe(msgOOB.sTargetCTNode))
end

-- Handler for the message to update stealth that comes from a client player who is controlling a shared npc and making a stealth roll (no permission to update npc CT actor on client)
function handleUpdateStealth(msgOOB)
	if not msgOOB or msgOOB.nStealthTotal == nil or msgOOB.sCTNodeId == nil or not msgOOB.user then return end

	-- Deserialize the number. Numbers are serialized as strings in the OOB msg.
	local nStealthTotal = tonumber(msgOOB.nStealthTotal)
	if nStealthTotal == nil then return end

	local bSecret = (msgOOB.bSecret == "1" or msgOOB.bSecret == 1 or msgOOB.bSecret == true)
	local sTargetCTNode = getActiveDuplicateCTNodePath(msgOOB.sCTNodeId)
	local bAllow = checkAndDisplayAllowOutOfCombatAndTurnChecks(sTargetCTNode)
	if bAllow then
		setNodeWithStealthValue(sTargetCTNode, nStealthTotal, bSecret)
		if OptionsManager.getOption(STEALTHTRACKER_SHOW_AFTER_STEALTH) == ON then
			local nodeCT = ActorManager.getCTNode(sTargetCTNode)
			displayStealthCheckInformationWithConditionAndVerboseChecks(nodeCT, FORCE_DISPLAY)
		end
	end
end

-- Check a CT node for a valid type.  Currently any non-empty type is valid but might be restricted in the future (i.e. Trap, Object, etc.)
function hasValidType(nodeCTActor)
    local sNpcType = DB.getText(nodeCTActor, "type", ""):lower() -- this is 'Race' on a PC sheet and 'type' (i.e. Object, Trap, Beast, etc) on an NPC sheet.
	return sNpcType ~= ""
        and not sNpcType:match("^%s*trap%s*$") -- TODO: Make this optional, defaulting to true.
        and not sNpcType:match("^%s*object%s*$") -- TODO: Make this optional, defaulting to true.
        and not isStealthTrackerDisabledForActor(nodeCTActor)
end

function insertBlankSeparatorIfNotEmpty(aTable)
	if #aTable > 0 then table.insert(aTable, "") end
end

function insertFormattedTextWithSeparatorIfNonEmpty(aTable, sFormattedText)
	insertBlankSeparatorIfNotEmpty(aTable)
	table.insert(aTable, sFormattedText)
end

function isDifferentFaction(vSource, vTarget)
	return ActorManager.getFaction(vSource) ~= ActorManager.getFaction(vTarget)
end

-- Function that checks an actor record to see if it's a friend (faction).  Can take an actor record or a node.
function isFriend(vActor)
	return vActor and ActorManager.getFaction(vActor) == "friend"
end

function isNpc(vActor)
	return ActorManager.getRecordType(vActor) == "npc"
end

function isPlayerStealthInfoDisabled()
	if OptionsManager and OptionsManager.getOption and OptionsManager.getOption(STEALTHTRACKER_VISIBILITY) == NONE then
		return true
	end
	if DB and DB.getValue and DB.getValue("options." .. STEALTHTRACKER_VISIBILITY, "") == NONE then
		return true
	end
	return false
end

-- Checks to see if the roll description (or drag info data) is a stealth skill roll.
function isStealthSkillRoll(sRollData)
	-- % is the escape character in Lua patterns.
	return sRollData and sRollData:lower():match("%[skill%] " .. LOCALIZED_STEALTH_LOWER)
end

-- Checks to see if the roll description (or drag info data) is a dexterity check roll.
function isDexterityCheckRoll(sRollData)
	return sRollData and sRollData:lower():match("%[check%] " .. LOCALIZED_DEXTERITY_LOWER)
end

function isStealthTrackerDisabledForActor(nodeCTActor)
    return nodeCTActor and DB.getText(nodeCTActor, "senses", ""):lower():match("no stealthtracker")
end

-- Function to process the condition of the source perceiving the target (source PP >= target stealth).  Returns a table representing the hidden actor otherwise, nil.
function isTargetHiddenFromSource(rSource, rTarget)
	if not rSource or not rTarget then return end

	-- If the target has a stealth value, compare the source's PP to it to see if the attacker perceives the hiding target.
	local rTargetCTNode = ActorManager.getCTNode(rTarget)
	if not rTargetCTNode then return end

    local data = nil
    local nPPSource, nPPMod = getPassivePerceptionWithModifier(rSource, rTarget)
	local nStealthTarget = getStealthNumberFromEffects(rTargetCTNode)
	if nStealthTarget ~= nil and nPPSource ~= nil then
        data = {
            source = rSource,
            sourcePP = nPPSource,
            sourcePPMod = nPPMod,
            target = rTarget,
            stealth = nStealthTarget
        }

		if nPPSource < nStealthTarget then
            data.hidden = true
        else
            data.hidden = false
		end
	end

	return data
end

function isUnidentifiedNpc(nodeRecord)
    return isNpc(nodeRecord) and DB.getValue(nodeRecord, "isidentified", 1) == 0
end

-- Valid nodes are more than just a type check now.
function isValidCTNode(nodeCT)
	return (hasValidType(nodeCT) or isFriend(nodeCT))
            and not isStealthTrackerDisabledForActor(nodeCT)
end

function modifyPassivePerceptionForActorEffects(rActor, nPP)
    local bAdv, bDisadv, nAddMod = getAdvDisadvForPerception(rActor)
    local nAdvBonus = bAdv and 5 or 0
    local nDisadvPenalty = bDisadv and -5 or 0
    return (nPP or 10) + nAdvBonus + nDisadvPenalty + (nAddMod or 0)
end

-- Function to notify the host of a stealth update so that the host can update items with proper permissions.
function notifyAttackFromStealth(sSourceCTNode, sTargetCTNode)
	if sSourceCTNode == nil or sTargetCTNode == nil then return end

	-- Setup the OOB message object, including the required type.
	local msgOOB = {}
	msgOOB.type = OOB_MSGTYPE_ATTACKFROMSTEALTH

	-- Capturing the username allows for the effect to be built so that it can be deleted by the client.
	msgOOB.sSourceCTNode = sSourceCTNode
	msgOOB.sTargetCTNode = sTargetCTNode
	Comm.deliverOOBMessage(msgOOB, "")
end

-- Function to notify the host of a stealth update request.  The arguments are the CT node identifier and the stealth total number.
function notifyUpdateStealth(sCTNodeId, nStealthTotal, bSecret)
	if sCTNodeId == nil or nStealthTotal == nil then return end

	-- Setup the OOB message object, including the required type.
	local msgOOB = {}
	msgOOB.type = OOB_MSGTYPE_UPDATESTEALTH

	-- Capturing the username allows for the effect to be built so that it can be deleted by the client.
	msgOOB.user = User.getUsername()
	msgOOB.sCTNodeId = sCTNodeId
	-- Note: numbers will be serialized as strings in the OOB msg.
	msgOOB.nStealthTotal = nStealthTotal
	if bSecret then
		msgOOB.bSecret = "1"
	end

	Comm.deliverOOBMessage(msgOOB, "")
end

-- Fires when the initiative is cleared via the CT menu.  Wired up in onInit() for the host only.
function onCombatResetEvent()
    if OptionsManager.getOption(STEALTHTRACKER_INIT_CLEAR) == ON then
        -- We are exiting initiative/combat, so clear all StealthTracker data from CT actors.
        local aOutput = {}
        getFormattedAndClearAllStealthTrackerDataFromCTIfAllowed(aOutput)
        displayTableIfNonEmpty(aOutput, FORCE_DISPLAY)
    end
end

function onDrop(nodetype, nodename, draginfo)
	-- In FGC, the drop event fires twice on CT entries without this deduping guard.
	if IS_FGC or checkFGC() then
		if LAST_DRAG_INFO == draginfo and
		   LAST_NODE_NAME == nodename and
		   LAST_NODE_TYPE == nodetype then
			LAST_DRAG_INFO = nil
			LAST_NODE_NAME = nil
			LAST_NODE_TYPE = nil
			return
		end

		LAST_DRAG_INFO = draginfo
		LAST_NODE_NAME = nodename
		LAST_NODE_TYPE = nodetype
	end

	local rSource = ActionsManager.decodeActors(draginfo)
	local rTarget = getActorSafe(nodename)
	onDropEvent(rSource, rTarget, draginfo)
    if type(CombatManager_onDrop) == "function" then
	    CombatManager_onDrop(nodetype, nodename, draginfo)
    end
end

-- Fires when something is dropped on the CT
function onDropEvent(rSource, rTarget, draginfo)
	if not USER_ISHOST or not rTarget or not rTarget.sCTNode or not draginfo then return end
	-- If rSource isn't nil and this isn't a 'number' drag from chat, then the drag came from a sheet and not the chat.
	local sDragType = (draginfo.getType and draginfo.getType()) or ""
	if rSource and sDragType ~= "number" then return end

	local sDragInfoData = (draginfo.getStringData and draginfo.getStringData()) or ""
	if sDragInfoData == "" and draginfo.getDescription then
		sDragInfoData = draginfo.getDescription() or ""
	end
	if sDragInfoData == "" then return end

	-- If the dropped item was a stealth roll or dex check, update the target creature node with the stealth value.
	local nStealthValue = draginfo.getNumberData()
	if nStealthValue and (isStealthSkillRoll(sDragInfoData) or isDexterityCheckRoll(sDragInfoData)) then
		local sLower = sDragInfoData:lower()
		local sTowerTag = (Interface and Interface.getString and Interface.getString("dicetower_tag")) or "tower"
		sTowerTag = (sTowerTag ~= "" and sTowerTag:lower()) or "tower"
		local bSecret = (draginfo.getSecret and draginfo.getSecret())
			or sLower:match("%[" .. sTowerTag .. "%]") ~= nil
			or sLower:match("%[tower%]") ~= nil
			or sLower:match("%[gm%]") ~= nil
			or false
		setNodeWithStealthValue(rTarget.sCTNode, nStealthValue, bSecret)
	end
end

-- Check for StealthTracker processing on a GenericAction (extension) Hide roll.
function onGenericActionPostRoll(rSource, rRoll)
	if rRoll and ActionsManager.doesRollHaveDice(rRoll) and rRoll.sType == GENACTROLL and (rRoll.sGenericAction == "Hide" or (rRoll.sGenericAction and rRoll.sGenericAction:lower() == "hide")) then
		displayProcessStealthUpdateForSkillHandlers(rSource, rRoll)
	end
end

function onInitiateSkill(rSource, rTarget, rRoll)
	local bProcessStealth = rSource and rRoll and isStealthSkillRoll(rRoll.sDesc)

	if bProcessStealth then
		local nodeSourceCT = ActorManager.getCTNode(rSource)
		if isPlayerStealthInfoDisabled() or (nodeSourceCT and CombatManager.isCTHidden(nodeSourceCT)) then
			rRoll.bSecret = true
		end
	end
end

function onPerformAction(draginfo, rActor, rRoll, ...)
	onInitiateSkill(rActor, nil, rRoll)
	if type(ActionsManager_performAction_Original) == "function" then
		return ActionsManager_performAction_Original(draginfo, rActor, rRoll, ...)
	end
end

function onRollAttack(rSource, rTarget, rRoll)
	if rSource and (not rSource.sCTNode or rSource.sCTNode == "") then
		local nodeCT = ActorManager.getCTNode(rSource)
		if not nodeCT and rSource.sCreatureNode and rSource.sCreatureNode ~= "" and CombatManager and CombatManager.getCTFromNode then
			nodeCT = CombatManager.getCTFromNode(rSource.sCreatureNode)
		end
		if nodeCT then
			rSource.sCTNode = getNodePathSafe(nodeCT) or ""
		end
	end

	-- Redirect rSource.sCTNode to active duplicate CT node if applicable
	if rSource and rSource.sCTNode and rSource.sCTNode ~= "" then
		local sNewPath = getActiveDuplicateCTNodePath(rSource.sCTNode)
		if sNewPath ~= rSource.sCTNode then
			rSource.sCTNode = sNewPath
		end
	end

	-- If target is nil, try to resolve it from the active duplicate CT node's targets
	if not rTarget and rSource and rSource.sCTNode ~= "" and TargetingManager and TargetingManager.getFullTargets then
		local aTargets = TargetingManager.getFullTargets(rSource)
		if aTargets and #aTargets > 0 then
			rTarget = aTargets[1]
		end
	end

	-- Redirect rTarget to correct duplicate if applicable
	if rTarget then
		rTarget = resolveTargetDuplicateCTNode(rSource, rTarget)
	end

	-- When attacks are rolled in the tower, the target is always nil.
	if not rTarget and rRoll and (rRoll.bSecret or rRoll.bTower) then
		displayTowerRoll()
	end

	displayProcessAttackFromStealth(rSource, rTarget)
end

-- Post-resolve observer for skill-type rolls. Runs AFTER the ruleset's own result handler.
function onRollSkill(rSource, rTarget, rRoll)
	-- Redirect rSource.sCTNode to active duplicate CT node if applicable
	if rSource and rSource.sCTNode and rSource.sCTNode ~= "" then
		local sNewPath = getActiveDuplicateCTNodePath(rSource.sCTNode)
		if sNewPath ~= rSource.sCTNode then
			rSource.sCTNode = sNewPath
		end
	end

	local bProcessStealth = rSource and rRoll and ActionsManager.doesRollHaveDice(rRoll) and isStealthSkillRoll(rRoll.sDesc)
	if bProcessStealth then
	    displayProcessStealthUpdateForSkillHandlers(rSource, rRoll)
    end
end

-- Handler for the 'st' and 'stealthtracker' slash commands in chat.
function processChatCommand(_, sParams)
	-- Only allow administrative subcommands when run on the host/DM system.
	local sFailedSubcommand = processHostOnlySubcommands(sParams)
	if sFailedSubcommand then
		displayChatMessage("Unrecognized subcommand: " .. sFailedSubcommand, SECRET)
	end
end

-- Chat commands that are for host only
function processHostOnlySubcommands(sSubcommand)
	-- Default/empty subcommand - What does the current CT actor not perceive?
	if sSubcommand == "" then
		-- This is the default subcommand for the host (/stealth with no subcommand). It will give a local only display of the actors hidden from the active CT actor.
		-- Get the node for the current CT actor.
		local nodeActiveCT = CombatManager.getActiveCT()
		if not nodeActiveCT then
			displayChatMessage("No active Combat Tracker actor.", SECRET)
		else
			displayStealthCheckInformationWithConditionAndVerboseChecks(nodeActiveCT, FORCE_DISPLAY)
		end

		return
	end

	-- Clear all stealth names from CT actors creature nodes.
	if sSubcommand == "clear" then
		local aOutput = {}
		getFormattedAndClearAllStealthTrackerDataFromCTIfAllowed(aOutput, true)
		displayTableIfNonEmpty(aOutput, FORCE_DISPLAY)
		return
	end

	-- Fallthrough/unrecognized subcommand
	return sSubcommand
end

function requestActivation(nodeEntry, bSkipBell)
    if type(CombatManager_requestActivation) == "function" and CombatManager_requestActivation ~= requestActivation then
        CombatManager_requestActivation(nodeEntry, bSkipBell)
    end
    if not isValidCTNode(nodeEntry) then return end

    local bOk, sErr = pcall(function()
        ensureStealthSkillExistsOnNpc(nodeEntry)
        displayStealthCheckInformationWithConditionAndVerboseChecks(nodeEntry, false)
    end)
    if not bOk and Debug and Debug.console then
        Debug.console("StealthTracker: error in requestActivation: " .. tostring(sErr))
    end
end

-- Function to encapsulate the setting of the name with stealth value.
function setNodeWithStealthValue(sCTNode, nStealthTotal, bSecret)
	if sCTNode == nil or nStealthTotal == nil then return end

	-- First, delete any existing Stealth effects on the CT node.
	local nodeCT = ActorManager.getCTNode(sCTNode)
	if not nodeCT then return end

	deleteAllStealthEffects(nodeCT)

	-- Then, add a new effect with the provided stealth value and make it be by user so that he/she can delete it from the CT on their own, if necessary.
	-- NOTE: When using addEffect to set effects, you must use the sCTNode and NOT the sCreatureNode (no effects on PC character sheet like in CT).
	local sEffectName = string.format("%s: %d", LOCALIZED_STEALTH, nStealthTotal)
	local nCurrentActorInit = DB.getValue(nodeCT, "initresult", 0)
	local nEffectExpirationInit = nCurrentActorInit - .1 -- .1 because we want it to tick right after their turn.
	local nEffectDuration = 0 -- according to 5e, actor should remain hidden until they do something to become visible (i.e. attack).
	if checkExpireActionAndRound() then -- but let the user override that via an option setting.
		nEffectDuration = 2  -- because the effect init we used is after the user's turn.
	end

	-- Check and see if the 'share none' option is enabled, or if the roll was made secretly/in the dice tower.  In that case or non-friendly npcs, we'll want the effect to be GM only.
	local nEffectGMOnly = booleanToNumber((bSecret and true or false)
										  or isPlayerStealthInfoDisabled()
										  or (isNpc(nodeCT) and not isFriend(nodeCT)))
	local rEffect = {
		sName = sEffectName,
		nInit = nEffectExpirationInit,
		nDuration = nEffectDuration,
		nGMOnly = nEffectGMOnly
	}

	-- Only show the chat announcement message if visibility is set to 'all' (Chat and Effects) and it is not a GM-only effect.
	local sVisibility = OptionsManager.getOption(STEALTHTRACKER_VISIBILITY)
	local bShowMsg = (sVisibility == ALL) and (nEffectGMOnly == 0)

	EffectManager.addEffect("", "", nodeCT, rEffect, bShowMsg)

	-- Explicitly set isgmonly on the newly created effect node if it is GM-only to ensure it is hidden from player CT
	if nEffectGMOnly == 1 then
		for _, nodeEffect in pairs(DB.getChildren(nodeCT, EFFECTS)) do
			if DB.getValue(nodeEffect, "label", "") == sEffectName then
				DB.setValue(nodeEffect, "isgmonly", "number", 1)
				break
			end
		end
	end
end

function validateTableOrNew(aTable)
	if aTable and type(aTable) == "table" then
		return aTable
	else
		return {}
	end
end
