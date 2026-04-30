--[[  FEATURE TODO
    For feature on token hover to display a panel with StealthTracker info (from CoreRPG):
                if TokenManager2 and TokenManager2.onHover then
                        TokenManager2.onHover(tokenMap, nodeCT, bOver);
                end
--]]
ALL = "all"
AWARE = "aware"
DEXTERITY = "dexterity"
EFFECTS = "effects"
FORCE_DISPLAY = true
GENACTROLL = "genactroll"
HIDDEN = "hidden"
IS_FGC = false
LAST_DRAG_INFO = nil
LAST_NODE_NAME = nil
LAST_NODE_TYPE = nil
LOCALIZED_DEXTERITY = "Dexterity"
LOCALIZED_DEXTERITY_LOWER = LOCALIZED_DEXTERITY:lower()
LOCALIZED_STEALTH = "Stealth"
LOCALIZED_STEALTH_ABV = "S"
LOCALIZED_STEALTH_LOWER = LOCALIZED_STEALTH:lower()
NONE = "none"
OFF = "off"
ON = "on"
OOB_MSGTYPE_UPDATESTEALTH = "updatestealth"
OOB_MSGTYPE_ATTACKFROMSTEALTH = "attackfromstealth"
SECRET = true
ST_STEALTH_DISABLED_OUT_OF_FORMAT = "Stealth processing disabled when out of %s."
STEALTHTRACKER_ALLOW_OUT_OF = "STEALTHTRACKER_ALLOW_OUT_OF"
STEALTHTRACKER_AWARE = "STEALTHTRACKER_AWARE"
STEALTHTRACKER_EXPIRE_EFFECT = "STEALTHTRACKER_EXPIRE_EFFECT"
STEALTHTRACKER_FACTION_FILTER = "STEALTHTRACKER_FACTION_FILTER"
STEALTHTRACKER_FRAME_STYLE = "STEALTHTRACKER_FRAME_STYLE"
STEALTHTRACKER_INIT_CLEAR = "STEALTHTRACKER_INIT_CLEAR"
STEALTHTRACKER_SHOW_AFTER_STEALTH = "STEALTHTRACKER_SHOW_AFTER_STEALTH"
STEALTHTRACKER_SHOW_EYE = "STEALTHTRACKER_SHOW_EYE"
STEALTHTRACKER_VERBOSE = "STEALTHTRACKER_VERBOSE"
STEALTHTRACKER_VISIBLE = "STEALTHTRACKER_VISIBLE"
STEALTHTRACKER_VISIBILITY = "STEALTHTRACKER_VISIBILITY"
TURN = "turn"
UNAWARE = "unaware"
UNIDENTIFIED = "(unidentified)"
USER_ISHOST = false
VISIBLE = "visible"

-- Configuration table for stealth effects to apply to observers
STEALTH_EFFECT_MODIFIERS = {
    ["cloak of elvenkind"] = -5
}

A_CHECK_FILTER = {
    "wisdom"
}
A_SKILL_FILTER = {
    "perception",
    "wisdom"
}

local ActionSkill_onRoll, ActionAttack_onAttack, CombatManager_onDrop, CombatManager_requestActivation
local _bAbilityBonusWarningLogged = false

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

-- Helper to safely check for effects, preferring the 5E-specific EffectManager5E if available.
local function hasEffectSafe(rActor, sEffect)
    if EffectManager5E and EffectManager5E.hasEffect then
        return EffectManager5E.hasEffect(rActor, sEffect)
    end
    return EffectManager.hasEffect(rActor, sEffect)
end

-- Helper to safely get an actor from a node/string, preferring the modern getActor method.
local function getActorSafe(v)
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

-- This function is required for all extensions to initialize variables and spit out the copyright and name of the extension as it loads
function onInit()
        IS_FGC = checkFGC()
        LOCALIZED_DEXTERITY = Interface.getString(DEXTERITY)
        LOCALIZED_DEXTERITY_LOWER = LOCALIZED_DEXTERITY:lower()
        LOCALIZED_STEALTH = Interface.getString("skill_value_stealth")
        LOCALIZED_STEALTH_ABV = LOCALIZED_STEALTH:sub(1, 1)
        LOCALIZED_STEALTH_LOWER = LOCALIZED_STEALTH:lower()
        USER_ISHOST = User.isHost()

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
                if CombatDropManager then
                        CombatDropManager.registerCallback(onDrop)
                else
                        CombatManager_onDrop = CombatManager.onDrop
                        CombatManager.onDrop = onDrop
                end

                CombatManager_requestActivation = CombatManager.requestActivation
                CombatManager.requestActivation = requestActivation

                -- OOB message registration for handling stealth updates that happen on clients.
                Comm.registerNextHandler(OOB_MSGTYPE_UPDATESTEALTH, handleUpdateStealth)
                Comm.registerNextHandler(OOB_MSGTYPE_ATTACKFROMSTEALTH, handleAttackFromStealth)
        end

        -- Roll skill handler override to add stealth tracking logic.
        ActionSkill_onRoll = ActionSkill.onRoll
        ActionSkill.onRoll = onRollSkill

        -- Roll attack handler override to check for attack from stealth.
        ActionAttack_onAttack = ActionAttack.onAttack
        ActionAttack.onAttack = onRollAttack

        -- Wiring into Generic Actions extension if it's available.
        if ActionsManager2 then
                ActionsManager2.registerPostRollHandler(onGenericActionPostRoll)
        end
end

function booleanToNumber(b)
	return b and 1 or 0
end

-- This is a wrapper for all check/skill roll handlers to update the CT stealth value from the ruleset roll results.
function checkAndDisplayAllowOutOfCombatAndTurnChecks(sCTNodeId)
	if sCTNodeId == nil then return false end

	local sAllowOutOf = OptionsManager.getOption(STEALTHTRACKER_ALLOW_OUT_OF)
	if sAllowOutOf == ALL then
		return true
	end

	local nodeCT = DB.findNode(sCTNodeId)
	if nodeCT == nil then return false end

	local bInCombat = CombatManager.isCombatActive()
	if bInCombat then
		if sAllowOutOf == TURN then
			return true
		end

		if CombatManager.isCTActive(nodeCT) then
			return true
		end
	end

	-- If the logic reaches this point, then the stealth processing was disabled by an option setting.
	local sReason = "combat"
	if bInCombat then sReason = "turn" end
	displayChatMessage(string.format(ST_STEALTH_DISABLED_OUT_OF_FORMAT, sReason), SECRET)
	return false
end

function checkExpireActionAndRound()
	return OptionsManager.isOption(STEALTHTRACKER_EXPIRE_EFFECT, ALL)
end

function checkFactionFilter()
	return OptionsManager.isOption(STEALTHTRACKER_FACTION_FILTER, ON)
end

function checkFGC()
	local sVersion = Interface.getVersionString()
	-- Unity versioning is currently 4.x.  Classic versioning is 3.x.
	return sVersion:match("^3%.")
end

function checkVerbosityMax()
	return OptionsManager.isOption(STEALTHTRACKER_VERBOSE, "max")
end

-- Function to walk the CT and clear all of the names of any appended stealth values.
function getFormattedAndClearAllStealthTrackerDataFromCTIfAllowed(aOutput, bForce)
	local bInitClearOption = OptionsManager.isOption(STEALTHTRACKER_INIT_CLEAR, ON)
	if not bForce and not bInitClearOption then return end

	-- Only clear all names if the option is set to do so.
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	for _, nodeCT in ipairs(lCombatTrackerActors) do
		deleteAllStealthEffects(nodeCT)
	end

	insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "Stealth data cleared from all Combat Tracker actors.")
end

function deleteAllStealthEffects(nodeCT)
	if not nodeCT then return end

	local aEffects = DB.getChildren(nodeCT, EFFECTS)
	for _, nodeEffect in pairs(aEffects) do
		if getStealthValueFromEffectNode(nodeEffect) then
			nodeEffect.delete()
		end
	end
end

function displayChatMessage(sText, bSecret)
	if sText == nil or sText == "" then return end

	local msg = {font = "emotefont", icon = "stealth_icon", text = sText}
	if bSecret then
		if OptionsManager.isOption(STEALTHTRACKER_SHOW_EYE, ON) then
			msg.secret = true
		end
		Comm.addChatMessage(msg)
	else
		Comm.deliverChatMessage(msg)
	end
end

-- Wrapper function to iterate over a table of strings and display them as a single chat message.
function displayTableIfNonEmpty(aOutput, bSecret)
	if not aOutput or #aOutput == 0 then return end

	local sFrameStyle = getMode()
	if sFrameStyle ~= "" then
		local msg = {font = "emotefont", icon = "stealth_icon", text = table.concat(aOutput, "\r\n")}
		msg.mode = sFrameStyle
		if bSecret then
			if OptionsManager.isOption(STEALTHTRACKER_SHOW_EYE, ON) then
				msg.secret = true
			end
			Comm.addChatMessage(msg)
		else
			Comm.deliverChatMessage(msg)
		end
	else
		for _, sMsg in ipairs(aOutput) do
			displayChatMessage(sMsg, bSecret)
		end
	end
end

function displayProcessAttackFromStealth(rSource, rTarget)
    if not USER_ISHOST then
        -- This logic must run on the host system to have the necessary permissions for name updates and to see all CT nodes.
        notifyAttackFromStealth(ActorManager.getCTNodeName(rSource), ActorManager.getCTNodeName(rTarget))
        return
    end

	if not rSource then return end

	-- Check for stealth on the source (attacker).
	local nStealthSource = getStealthNumberFromEffects(ActorManager.getCTNode(rSource))
	if nStealthSource == nil then return end

	local aOutput = {}
	getFormattedPerformAttackFromStealth(rSource, rTarget, nStealthSource, aOutput)
	displayTableIfNonEmpty(aOutput, SECRET)

	-- If the attacker makes an attack, then they are no longer stealthing (v3.2 option dependent).
	local sExpireOption = OptionsManager.getOption(STEALTHTRACKER_EXPIRE_EFFECT)
	if sExpireOption ~= NONE then
		deleteAllStealthEffects(ActorManager.getCTNode(rSource))
	end
end

function displayProcessStealthUpdateForSkillHandlers(rSource, rRoll)
	-- Get the stealth roll total from the roll object.
	local nStealthTotal = ActionsManager.getDiceTotal(rRoll)
	local nodeCTSource = ActorManager.getCTNode(rSource)
	if not nodeCTSource then return end

	local sCTNodeId = nodeCTSource.getNodeName()
	if USER_ISHOST then
		if checkAndDisplayAllowOutOfCombatAndTurnChecks(sCTNodeId) then
			setNodeWithStealthValue(sCTNodeId, nStealthTotal)

			-- If the option to show a summary after a stealth roll is enabled, then display it.
			if OptionsManager.isOption(STEALTHTRACKER_SHOW_AFTER_STEALTH, ON) then
				displayStealthCheckInformationWithConditionAndVerboseChecks(nodeCTSource, false)
			end
		end
	else
		-- If this is a client, we need to notify the host to update the CT actor's name.
		notifyUpdateStealth(sCTNodeId, nStealthTotal)
	end
end

function displayStealthCheckInformationWithConditionAndVerboseChecks(nodeCTActor, bForce)
	if not nodeCTActor then return end

	local aOutput = {}
	getFormattedStealthDataFromCT(nodeCTActor, aOutput)
	displayTableIfNonEmpty(aOutput, not bForce)
end

function displayTowerRoll()
	displayChatMessage("The actor rolled in the tower. StealthTracker cannot see tower rolls. Drag it manually to the CT actor entry to update.", SECRET)
end

-- Checks for the presence of a debilitating condition on the actor (i.e. blinded, etc) that would impact their perception of others.
-- Returns the name of the condition if found, nil otherwise.
function getActorDebilitatingCondition(rActor)
	if not rActor then return end

	local aConditions = {"blinded", "unconscious", "incapacitated", "paralyzed", "stunned"}
	for _, sCondition in ipairs(aConditions) do
		if hasEffectSafe(rActor, sCondition) then
			return sCondition
		end
	end
end

-- This is a fallback function to calculate a default passive perception from the wisdom score for when the sheet is not available.
function getDefaultPassivePerception(nodeCreature)
	if not nodeCreature then return 10 end

	local nPP = 10
	local nWisMod = getAbilityBonusSafe(nodeCreature, "wisdom")
	nPP = nPP + nWisMod

	-- Add in proficiency bonus if NPC.
	if isNpc(nodeCreature) then
		nPP = nPP + getProficiencyBonus(nodeCreature)
	end

	return nPP
end

-- Function to check if the target perceives the attacker under stealth, returning true if so and false if not.
function doesTargetPerceiveAttackerFromStealth(nAttackerStealth, rAttacker, rObserver)
       if nAttackerStealth == nil or not rObserver then return false end

       local nPPObserver = getPassivePerceptionNumber(rObserver)
    if nPPObserver == nil then return false end

    -- Apply any modifiers from the attacker's effects acting on the observer (i.e. Cloak of Elvenkind)
    nPPObserver = nPPObserver + getStealthEffectModifier(rAttacker)

       return nPPObserver >= nAttackerStealth
end

function ensureStealthSkillExistsOnNpc(nodeCT)
    if not nodeCT or not isNpc(nodeCT) or DB.getChild(nodeCT, "skills") then return end

    local sSkills = DB.getText(nodeCT, "skills", "")
    if sSkills:lower():match(LOCALIZED_STEALTH_LOWER) then return end

    -- NPC lacks stealth skill.  Add it with its dex bonus.
    local nDexBonus = getAbilityBonusSafe(nodeCT, "dexterity")
    local sSeparator = (sSkills == "") and "" or ", "
    DB.setValue(nodeCT, "skills", "string", string.format("%s%s%s %+d", sSkills, sSeparator, LOCALIZED_STEALTH, nDexBonus))
end

function getFormattedPPString(nPPEffective, nPPMod)
    if nPPMod == 0 then
        return string.format("%d", nPPEffective)
    end
    -- Use %+d to enforce sign display (e.g. -5 or +5)
    return string.format("%d (%+d)", nPPEffective, nPPMod)
end

function getPassivePerceptionWithModifier(rObserver, rSubject)
    local nPP = getPassivePerceptionNumber(rObserver) or 0
    local nMod = getStealthEffectModifier(rSubject)
    return nPP + nMod, nMod
end

function getFormattedPerformAttackFromStealth(rSource, rTarget, nStealthSource, aOutput)
	if not rSource or nStealthSource == nil then return end

	-- This is the core logic of the attack from stealth check.
	-- If the target is nil, we can't perform the check (i.e. tower roll).
	if not rTarget then return end

	-- Check for target hiding (if target is hiding, attacker might not see it, so ADVATK check is deferred to manual GM check).
	local rSourceHidden = isTargetHiddenFromSource(rTarget, rSource)
	if rSourceHidden and rSourceHidden.hidden then
		-- Source (attacker) is hidden from Target. Warn the GM.
		insertFormattedTextWithSeparatorIfNonEmpty(aOutput, string.format("Attacker is hidden from %s. Attack at advantage?", ActorManager.getDisplayName(rTarget)))
	else
		-- Check for attacker hiding.
		local sMsgText
        local rTargetHidden = isTargetHiddenFromSource(rSource, rTarget)
		if rTargetHidden and not rTargetHidden.hidden then
            local nPPEffective, nPPMod = getPassivePerceptionWithModifier(rTarget, rSource)
            local sPPDisplay = getFormattedPPString(nPPEffective, nPPMod)

				local sStats = string.format("(%s %s: %d, %s PP: %s)",
                                                                         ActorManager.getDisplayName(rSource),
                                                                         LOCALIZED_STEALTH_ABV,
                                                                         nStealthSource,
                                                                         ActorManager.getDisplayName(rTarget),
                                                                         sPPDisplay)
				if not doesTargetPerceiveAttackerFromStealth(nStealthSource, rSource, rTarget) then
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

    local sCTSourceDisplayName = ActorManager.getDisplayName(nodeCTSource)
    if isBlank(sCTSourceDisplayName) or isUnidentifiedNpc(nodeCTSource) then
        sCTSourceDisplayName = getUnidentifiedName(nodeCTSource)
    end

    local nStealthSource = getStealthNumberFromEffects(nodeCTSource)
        -- Loop through the CT, getSortedCombatantList() returns the list ordered as-is in CT (sorted by the CombatManager.sortfuncDnD sort function loaded by the 5e ruleset) and is never nil
        local lCombatTrackerActors = CombatManager.getSortedCombatantList()
        for _, nodeCT in ipairs(lCombatTrackerActors) do
        if isValidCTNode(nodeCT) then  -- hasValidType(nodeCT) or isFriend(nodeCT)
            -- Two checks will be needed each iteration.  One for visible/hidden and the other for aware/unaware.
            local rIterationActor = getActorSafe(nodeCT)
            if rIterationActor then
                local sIterationActorDisplayName = ActorManager.getDisplayName(rIterationActor)
                if isBlank(sIterationActorDisplayName) or isUnidentifiedNpc(nodeCT) then
                    sIterationActorDisplayName = getUnidentifiedName(nodeCT)
                end

                local sDebilitatingCondition = getActorDebilitatingCondition(rIterationActor)
                if rCurrentActor.sCTNode ~= rIterationActor.sCTNode and  -- Current actor doesn't equal iteration actor (no need to report on the actors own visibility!).
                   (not checkFactionFilter() or isDifferentFaction(nodeCTSource, nodeCT)) then  -- friendly faction filter
                    local rHiddenTarget = isTargetHiddenFromSource(rCurrentActor, rIterationActor)
                    if rHiddenTarget and sDebilitatingCondition == nil then
                        local sText = string.format("%s - %s: %d", -- ex: ActorName - Stealth: 8
                                                    sIterationActorDisplayName,
                                                    LOCALIZED_STEALTH,
                                                    rHiddenTarget.stealth)
                        -- New logic to append PP info if modified
                        local nBasePP = getPassivePerceptionNumber(rIterationActor)
                        if rHiddenTarget.sourcePP ~= nBasePP then
                            local nMod = rHiddenTarget.sourcePP - nBasePP
                            local sPPDisplay = getFormattedPPString(rHiddenTarget.sourcePP, nMod)
                            sText = sText .. string.format(" [PP %s]", sPPDisplay)
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
                        if doesTargetPerceiveAttackerFromStealth(nStealthSource, rCurrentActor, rIterationActor) then
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
    if not OptionsManager.isOption(STEALTHTRACKER_VISIBLE, NONE) then
        if not OptionsManager.isOption(STEALTHTRACKER_VISIBLE, VISIBLE) then
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

        if not OptionsManager.isOption(STEALTHTRACKER_VISIBLE, HIDDEN) then
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

    if not OptionsManager.isOption(STEALTHTRACKER_AWARE, NONE) then
        if not OptionsManager.isOption(STEALTHTRACKER_AWARE, UNAWARE) then
            if #rStealthData.aware > 0 then
                -- Now, let's display a summary message and append the output strings from above appended to the end.
                local sText = string.format("%s (%s: %d) is seen by:\r%s",
                                            sCTSourceDisplayName,
                                            LOCALIZED_STEALTH,
                                            nStealthSource,
                                            table.concat(rStealthData.aware, "\r"))
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
            else
                if nStealthSource ~= nil and checkVerbosityMax() then
                    local sText = string.format("There are no actors that can see %s.",
                                                sCTSourceDisplayName)
                    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
                end
            end
        end

        if not OptionsManager.isOption(STEALTHTRACKER_AWARE, AWARE) then
            if #rStealthData.unaware > 0 then
                -- Now, let's display a summary message and append the output strings from above appended to the end.
                local sText = string.format("%s (%s: %d) is hidden from:\r%s",
                                            sCTSourceDisplayName,
                                            LOCALIZED_STEALTH,
                                            nStealthSource,
                                            table.concat(rStealthData.unaware, "\r"))
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
            else
                if nStealthSource ~= nil and checkVerbosityMax() then
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

    return modifyPassivePerceptionForActorEffects(nodeCreature, nPP)
end

function getAdvDisadvForPerception(nodeCreature)
    local bADV, bDIS = false, false
    if hasEffectSafe(nodeCreature, "ADVSKILL") then
        bADV = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "ADVSKILL", A_SKILL_FILTER)) > 0 then
        bADV = true
    elseif hasEffectSafe(nodeCreature, "ADVCHK") then
        bADV = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "ADVCHK", A_CHECK_FILTER)) > 0 then
        bADV = true
    end
    if hasEffectSafe(nodeCreature, "DISSKILL") then
        bDIS = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "DISSKILL", A_SKILL_FILTER)) > 0 then
        bDIS = true
    elseif hasEffectSafe(nodeCreature, "DISCHK") then
        bDIS = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "DISCHK", A_CHECK_FILTER)) > 0 then
        bDIS = true
    end

    -- if EffectManager5E.hasEffectCondition(nodeCreature, "Frightened") then
    --     bDIS = true
    -- end

    -- Get ability modifiers
    local aAddDice, nAddMod, _ = EffectManager5E.getEffectsBonus(nodeCreature, {"CHECK"}, false, A_CHECK_FILTER)
    local aSkillAddDice, nSkillAddMod, nSkillEffectCount = EffectManager5E.getEffectsBonus(nodeCreature, {"SKILL"}, false, A_SKILL_FILTER)
    if (nSkillEffectCount > 0) then
        for _,v in ipairs(aSkillAddDice) do
            table.insert(aAddDice, v)
        end
        nAddMod = nAddMod + nSkillAddMod;
    end

    -- Get ability modifiers
    local nBonusStat, nBonusEffects = 0, 0
    if ActorManager5E.getAbilityEffectsBonus then
        nBonusStat, nBonusEffects = ActorManager5E.getAbilityEffectsBonus(nodeCreature, "wisdom")
    elseif getAbilityBonusSafe(nodeCreature, "wisdom") then
        nBonusStat = getAbilityBonusSafe(nodeCreature, "wisdom")
        nBonusEffects = 1 -- Assumed if it returns a value
    end
    if nBonusEffects > 0 then
        nAddMod = nAddMod + nBonusStat
    end

    -- Get exhaustion modifiers
    local nExhaustMod, nExhaustCount = EffectManager5E.getEffectsBonus(nodeCreature, {"EXHAUSTION"}, true)
    if nExhaustCount > 0 then
        if nExhaustMod >= 1 then
            bDIS = true
        end
    end

    return bADV, bDIS, nAddMod
end

function getProficiencyBonus(vActor)
    local nStatScore
    if ActorManager.isPC(vActor) then
        local nodeActor = ActorManager.getCreatureNode(vActor);
        nStatScore = DB.getValue(nodeActor, "profbonus", 0);
    else
        local nodeActor = ActorManager.getCTNode(vActor) or ActorManager.getCreatureNode(vActor);
        nStatScore = getProficiencyBonusForNPCChallengeRating(nodeActor) or 0;
    end

    return nStatScore
end

function getProficiencyBonusForNPCChallengeRating(nodeActor)
    local sCR = DB.getValue(nodeActor, "cr", "")
    return CR_PROFICIENCY_MAP[sCR] or 0
end

local CR_PROFICIENCY_MAP = {
    ["0"] = 2, ["1/8"] = 2, ["1/4"] = 2, ["1/2"] = 2,
    ["1"] = 2, ["2"] = 2, ["3"] = 2, ["4"] = 2,
    ["5"] = 3, ["6"] = 3, ["7"] = 3, ["8"] = 3,
    ["9"] = 4, ["10"] = 4, ["11"] = 4, ["12"] = 4,
    ["13"] = 5, ["14"] = 5, ["15"] = 5, ["16"] = 5,
    ["17"] = 6, ["18"] = 6, ["19"] = 6, ["20"] = 6,
    ["21"] = 7, ["22"] = 7, ["23"] = 7, ["24"] = 7,
    ["25"] = 8, ["26"] = 8, ["27"] = 8, ["28"] = 8,
    ["29"] = 9, ["30"] = 9
}

function getStealthEffectModifier(vActor)
    if not vActor then return 0 end

    local rActor = ActorManager.resolveActor(vActor)
    if not rActor then return 0 end

    local nTotalMod = 0
    for sEffectName, nMod in pairs(STEALTH_EFFECT_MODIFIERS) do
        -- Check if the actor has the effect (case-insensitive check is handled by EffectManager implicitly or we assume standard casing?)
        -- EffectManager5E.hasEffect is case-insensitive.
        if EffectManager5E.hasEffect(rActor, sEffectName) then
            nTotalMod = nTotalMod + nMod
        end
    end

    return nTotalMod
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
                local sMatch = string.match(component, pattern)
                if sMatch then
                        sExtractedStealth = sMatch
                end
        end

        return sExtractedStealth
end

function getUnidentifiedName(nodeRecord)
    local unidentifiedName = DB.getValue(nodeRecord, "nonid_name", UNIDENTIFIED)
    if isBlank(unidentifiedName) then
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

        if checkAndDisplayAllowOutOfCombatAndTurnChecks(msgOOB.sCTNodeId) then
                setNodeWithStealthValue(msgOOB.sCTNodeId, nStealthTotal)
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

function isBlank(sTest)
    if type(sTest) ~= "string" then
        return false
    end

    local sCooked = string.gsub(sTest, "%s+", "")
    if sCooked == "" then
        return true
    else
        return false
    end
end

-- Checks to see if the roll description (or drag info data) is a dexterity check roll.
function isDexterityCheckRoll(sRollData)
        -- % is the escape character in Lua patterns.
        return sRollData and sRollData:lower():match("%[check%] " .. LOCALIZED_DEXTERITY_LOWER)
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
        return OptionsManager.isOption(STEALTHTRACKER_VISIBILITY, NONE)
end

-- Checks to see if the roll description (or drag info data) is a stealth skill roll.
function isStealthSkillRoll(sRollData)
        -- % is the escape character in Lua patterns.
        return sRollData and sRollData:lower():match("%[skill%] " .. LOCALIZED_STEALTH_LOWER)
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
    local nPPSource = getPassivePerceptionNumber(rSource)
        local nStealthTarget = getStealthNumberFromEffects(rTargetCTNode)
        if nStealthTarget ~= nil and nPPSource ~= nil then
        -- Apply modifiers from the target (hider) to the source (observer)
        nPPSource = nPPSource + getStealthEffectModifier(rTarget)

        data = {
            source = rSource,
            sourcePP = nPPSource,
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

function modifyPassivePerceptionForActorEffects(nodeCreature, nPP)
    local bAdv, bDisadv, nAddMod = getAdvDisadvForPerception(nodeCreature)
    local nAdvBonus = bAdv and 5 or 0
    local nDisadvPenalty = bDisadv and -5 or 0
    return nPP + nAdvBonus + nDisadvPenalty + nAddMod
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
function notifyUpdateStealth(sCTNodeId, nStealthTotal)
        if sCTNodeId == nil or nStealthTotal == nil then return end

        -- Setup the OOB message object, including the required type.
        local msgOOB = {}
        msgOOB.type = OOB_MSGTYPE_UPDATESTEALTH

        -- Capturing the username allows for the effect to be built so that it can be deleted by the client.
        msgOOB.user = User.getUsername()
        msgOOB.sCTNodeId = sCTNodeId
        -- Note: numbers will be serialized as strings in the OOB msg.
        msgOOB.nStealthTotal = nStealthTotal

        Comm.deliverOOBMessage(msgOOB, "")
end

-- Fires when the initiative is cleared via the CT menu.  Wired up in onInit() for the host only.
function onCombatResetEvent()
    if OptionsManager.isOption(STEALTHTRACKER_INIT_CLEAR, ON) then
        -- We are exiting initiative/combat, so clear all StealthTracker data from CT actors.
        local aOutput = {}
        getFormattedAndClearAllStealthTrackerDataFromCTIfAllowed(aOutput)
        displayTableIfNonEmpty(aOutput, FORCE_DISPLAY)
    end
end

function onDrop(nodetype, nodename, draginfo)
        -- I don't know why this weird hack is needed, but it prevents the drop from firing twice.  It is FGC only.
        if IS_FGC then
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
        if CombatManager_onDrop then
                CombatManager_onDrop(nodetype, nodename, draginfo)
        end
end

-- Fires when something is dropped on the CT
function onDropEvent(rSource, rTarget, draginfo)
        -- If rSource isn't nil, then the drag came from a sheet and not the chat.
        if rSource or not USER_ISHOST or not rTarget or not rTarget.sCTNode or not draginfo then return end

        local sDragInfoData = draginfo.getStringData()
        if sDragInfoData == nil or sDragInfoData == "" then return end

        -- If the dropped item was a stealth roll or dex check, update the target creature node with the stealth value.
        local nStealthValue = draginfo.getNumberData()
        if nStealthValue and (isStealthSkillRoll(sDragInfoData) or isDexterityCheckRoll(sDragInfoData)) then
                setNodeWithStealthValue(rTarget.sCTNode, nStealthValue)
        end
end

-- Check for StealthTracker processing on a GenericAction (extension) Hide roll.
function onGenericActionPostRoll(rSource, rRoll)
        if rRoll and ActionsManager.doesRollHaveDice(rRoll) and rRoll.sType == GENACTROLL and rRoll.sGenericAction == "Hide" then
                ActionsManager2.decodeAdvantage(rRoll) -- this is done automatically for ruleset (i.e. Stealth) rolls
                displayProcessStealthUpdateForSkillHandlers(rSource, rRoll)
        end
end

function onRollAttack(rSource, rTarget, rRoll)
        if ActionAttack_onAttack then
                ActionAttack_onAttack(rSource, rTarget, rRoll)
        end

        -- When attacks are rolled in the tower, the target is always nil.
        if not rTarget and rRoll.bSecret then
                displayTowerRoll()
        end

        displayProcessAttackFromStealth(rSource, rTarget)
end

-- NOTE: The roll handler runs on whatever system throws the dice, so it does run on the clients... unlike the way the CT events are wired up to the host only (in onInit()).
-- This is the handler that we wire up to override the default roll handler.  We can do our logic, then call the stored action handler (via onInit()), and finally finish up with more logic.
function onRollSkill(rSource, rTarget, rRoll)
        -- Check the arguments used in this function.  Only process stealth if both are populated.  Never return prior to calling the default handler from the ruleset (below, ActionSkill_onRoll(rSource, rTarget, rRoll))
        local bProcessStealth = rSource and rRoll and ActionsManager.doesRollHaveDice(rRoll) and isStealthSkillRoll(rRoll.sDesc)

        -- If we are processing stealth, update the roll display to remove any existing stealth info.
        if bProcessStealth then
                -- For PCs, sCreatureNode is their character sheet node.  For NPCs, it's the CT node (i.e. same as sCTNode).
                -- This is important because when the game loads, the CT node name for PCs is lost... it's reloaded from their character sheet node on initialization.
                -- This isn't the case for NPCs, which retain their modified name on game load.
                -- Check to see if the current actor is a npc and not visible.  If so, make the roll as secret/tower.
                if isPlayerStealthInfoDisabled() or (isNpc(rSource) and CombatManager.isCTHidden(rSource)) then
                        rRoll.bSecret = true
                end
        end

        -- Call the default action that happens when a skill roll occurs in the ruleset.
        if ActionSkill_onRoll then
                ActionSkill_onRoll(rSource, rTarget, rRoll)
        end
        if not bProcessStealth then return end

        displayProcessStealthUpdateForSkillHandlers(rSource, rRoll)
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
    if CombatManager_requestActivation then
        CombatManager_requestActivation(nodeEntry, bSkipBell)
    end
    if not isValidCTNode(nodeEntry) then return end

    ensureStealthSkillExistsOnNpc(nodeEntry)
        displayStealthCheckInformationWithConditionAndVerboseChecks(nodeEntry, false)
end

-- Function to encapsulate the setting of the name with stealth value.
function setNodeWithStealthValue(sCTNode, nStealthTotal)
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

        -- Check and see if the 'share none' option is enabled.  In that case or non-friendly npcs, we'll want the effect to be GM only.
        local nEffectGMOnly = booleanToNumber(isPlayerStealthInfoDisabled()
                                                                                  or (isNpc(nodeCT) and not isFriend(nodeCT)))
        local rEffect = {
                sName = sEffectName,
                nInit = nEffectExpirationInit,
                nDuration = nEffectDuration,
                nGMOnly = nEffectGMOnly
        }

        EffectManager.addEffect("", "", nodeCT, rEffect, true)
end

function validateTableOrNew(aTable)
        if aTable and type(aTable) == "table" then
                return aTable
        else
                return {}
        end
end
