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

A_CHECK_FILTER = {
    "wisdom"
}
A_SKILL_FILTER = {
    "perception",
    "wisdom"
}

local ActionSkill_onRoll, ActionAttack_onAttack, CombatManager_onDrop, CombatManager_requestActivation

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
			CombatManager_onDrop = CombatDropManager.onLegacyDropEvent
			CombatDropManager.onLegacyDropEvent = onDrop
		else
			CombatManager_onDrop = CombatManager.onDrop
			CombatManager.onDrop = onDrop
		end

        CombatManager_requestActivation = CombatManager.requestActivation
        CombatManager.requestActivation = requestActivation

		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_UPDATESTEALTH, handleUpdateStealth)
		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_ATTACKFROMSTEALTH, handleAttackFromStealth)

		-- Register chat commands for host only.
		Comm.registerSlashHandler("stealth", processChatCommand)
	end

	-- Unlike the Custom Turn and Init events above, the dice result handler must be registered on host and client.
	ActionSkill_onRoll = ActionSkill.onRoll
	ActionSkill.onRoll = onRollSkill
	ActionsManager.registerResultHandler("skill", onRollSkill)
	ActionAttack_onAttack = ActionAttack.onAttack
	ActionAttack.onAttack = onRollAttack
	ActionsManager.registerResultHandler("attack", onRollAttack)

	-- Compatibility with Generic Actions extension so that Hide action is treated as Stealth skill check.
	if ActionGeneral then
		ActionsManager.registerPostRollHandler(GENACTROLL, onGenericActionPostRoll)
	end
end

-- Alphebetical list of functions below (onInit() above was an exception)

function booleanToNumber(bValue)
	return bValue == true and 1 or bValue == false and 0
end

function checkAllowOutOfCombat()
	return OptionsManager.isOption(STEALTHTRACKER_ALLOW_OUT_OF, ALL)
end

function checkAllowOutOfTurn()
	return OptionsManager.isOption(STEALTHTRACKER_ALLOW_OUT_OF, TURN) or
		   checkAllowOutOfCombat()
end

function checkAndDisplayAllowOutOfCombatAndTurnChecks(vActor)
	if checkAndDisplayCTInactiveAndOutsideOfCombatStealthDisallowed() then return false end

	local nodeCT = ActorManager.getCTNode(vActor)
	if CombatManager.getActiveCT() ~= nodeCT and not checkAllowOutOfTurn() then
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
	local nMajor = Interface.getVersion()
	return nMajor < 4
end

function checkShowEye()
    return OptionsManager.isOption(STEALTHTRACKER_SHOW_EYE, ON)
end

function checkVerbosityMax()
	return OptionsManager.isOption(STEALTHTRACKER_VERBOSE, "max")
end

function checkVerbosityOff()
	return OptionsManager.isOption(STEALTHTRACKER_VERBOSE, OFF)
end

-- Deletes all of the stealth effects for a CT node (no expiration warning because this is cleanup and not effect usage causing the deletion).
function deleteAllStealthEffects(nodeCT)
	if not nodeCT then return end

	for _, nodeEffect in pairs(DB.getChildren(nodeCT, EFFECTS)) do
		if getStealthValueFromEffectNode(nodeEffect) then
			nodeEffect.delete()
		end
	end
end

-- Puts a message in chat that is broadcast to everyone attached to the host (including the host) if bSecret is true, otherwise local only.
function displayChatMessage(sFormattedText, bSecret)
	if sFormattedText == nil then return end

    local sMode = getMode()
	local msg = {font = "msgfont", icon = "stealth_icon", secret = checkShowEye(), text = sFormattedText, mode = sMode}  -- secret true shows the cross eye icon, wasting space
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
								ActorManager.getDisplayName(vActor),
								sCondition)
	displayChatMessage(sText, SECRET)
end

-- Logic to process an attack from stealth (for checking if enemies could have been attacked with advantage, etc).
function displayProcessAttackFromStealth(rSource, rTarget)
	-- if no source or no roll then exit, skipping StealthTracker processing.
	if not rSource or rSource.sCTNode == nil or rSource.sCTNode == "" then return end

	-- Extract the stealth number from the source, if available.  It's used later in this function at a couple spots.
	local nodeSourceCT = ActorManager.getCTNode(rSource)
	if not nodeSourceCT then return end

	if not USER_ISHOST then
		-- For clients notify of an action from stealth and then exit.  Host handler will pick up message and run code after this block.
		notifyAttackFromStealth(rSource.sCTNode, (rTarget and rTarget.sCTNode) or "")
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
			local sMsgText = string.format("Target hidden. Attack possible? (%s %s: %d, %s PP: %d).",
											ActorManager.getDisplayName(rTarget),
											LOCALIZED_STEALTH_ABV,
											rHiddenTarget.stealth,
											ActorManager.getDisplayName(rSource),
											rHiddenTarget.sourcePP)
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
	if rSource.sCTNode ~= "" and ActionsManager.doesRollHaveDice(rRoll) then
		-- Calculate the stealth roll so that it's available to put in the creature effects.  Advantage already decoded when coming from a 5E ruleset Stealth roll.
		local nStealthTotal = ActionsManager.total(rRoll)
		-- If the source of the roll is a npc sheet shared to a player, notify the host to update the stealth value.
		if USER_ISHOST then
			-- The CT node and the character sheet node are different nodes.  Updating the name on the CT node only updates the CT and not their character sheet value.
			if checkAndDisplayAllowOutOfCombatAndTurnChecks(rSource.sCTNode) then
				setNodeWithStealthValue(rSource.sCTNode, nStealthTotal)
                -- Display the stealth information now that the Stealth roll has been made so the DM can take advantage of the info if it all happens on the same turn (i.e. hide, then attack).
                if OptionsManager.isOption(STEALTHTRACKER_SHOW_AFTER_STEALTH, ON) then
                    local nodeCT = ActorManager.getCTNode(rSource.sCTNode)
                    displayStealthCheckInformationWithConditionAndVerboseChecks(nodeCT, FORCE_DISPLAY)
                end
			end
		elseif isPlayerStealthInfoDisabled() and not checkVerbosityOff() then -- TODO: This condition is a candidate for earlier trapping in an onRoll() overrided.  Then we could encode it to the tower and issue the roll.
			local output = string.format("The DM has StealthTracker info set to hidden.  Use the dice tower to make your %s roll.", LOCALIZED_STEALTH)
			displayChatMessage(output, false)
		else
			notifyUpdateStealth(rSource.sCTNode, nStealthTotal)
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
function doesTargetPerceiveAttackerFromStealth(nAttackerStealth, rTarget)
	if nAttackerStealth == nil or not rTarget then return false end

	local nPPTarget = getPassivePerceptionNumber(rTarget)
	return nPPTarget ~= nil and nPPTarget >= nAttackerStealth
end

function ensureStealthSkillExistsOnNpc(nodeCT)
	if not nodeCT then return end

	local rCurrentActor = ActorManager.resolveActor(nodeCT)
	if not rCurrentActor or not isNpc(rCurrentActor) then return end

	-- Consider the dex mod in any Stealth skill added to NPC sheet.  Bonus is always there, so chain.
	local nDexMod = ActorManager5E.getAbilityBonus(nodeCT, DEXTERITY)
	local sStealthWithMod = LOCALIZED_STEALTH .. " "
	if nDexMod >= 0 then
		sStealthWithMod = sStealthWithMod .. "+"
	end

	sStealthWithMod = sStealthWithMod .. nDexMod -- Ex: Stealth +0 or Stealth -2
	local rSkillsNode = nodeCT.getChild("skills")
	if not rSkillsNode then  -- NPC sheets are not guaranteed to have the Skills node.
		DB.setValue(nodeCT, "skills", "string", sStealthWithMod)
	else
		local sSkills = rSkillsNode.getText()
		-- Skip if Stealth is already there because resetting it due to dex change mid-combat would be rare and might not account for other modifiers.
		if not sSkills:match(LOCALIZED_STEALTH .. " [+-]%d") then
			-- Prepend the zero Stealth bonus to the skills (didn't bother sorting which would require tokenization, table sort, and joining).
			local sNewSkillsValue = sStealthWithMod .. ", " .. sSkills
			-- Trim off any trailing comma followed by zero or more whitespace.
			rSkillsNode.setValue(sNewSkillsValue:gsub("^%s*(.-),%s*$", "%1"))
		end
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
											ActorManager.getDisplayName(rActor))
				insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sText)
			end
		else
			EffectManager.expireEffect(nodeCT, nodeLastEffectWithStealth, 0)
		end
	end
end

function getActorDebilitatingCondition(vActor)
	local rActor = ActorManager.resolveActor(vActor)
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
		if EffectManager5E.hasEffect(rActor, sCondition) then return sCondition end
	end

	return nil
end

function getDefaultPassivePerception(nodeCreature)
    return 10 + ActorManager5E.getAbilityBonus(nodeCreature, "wisdom") + getProficiencyBonus(nodeCreature)
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

-- Function to do the 'attack from stealth' comparison where the attacker could have advantage if the target doesn't perceive the attacker (chat msg displayed).
-- This is called from the host only.
function getFormattedPerformAttackFromStealth(rSource, rTarget, nStealthSource, aOutput)
	if not rSource or not rTarget or nStealthSource == nil then return end

	aOutput = validateTableOrNew(aOutput)
	local sMsgText
    local rTargetHidden = isTargetHiddenFromSource(rSource, rTarget)
	if rTargetHidden and not rTargetHidden.hidden then
		local sStats = string.format("(%s %s: %d, %s PP: %d)",
									 ActorManager.getDisplayName(rSource),
									 LOCALIZED_STEALTH_ABV,
									 nStealthSource,
									 ActorManager.getDisplayName(rTarget),
									 getPassivePerceptionNumber(rTarget))
		if not doesTargetPerceiveAttackerFromStealth(nStealthSource, rTarget) then
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

	local rCurrentActor = ActorManager.resolveActor(nodeCTSource)
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
            local rIterationActor = ActorManager.resolveActor(nodeCT)
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
                        if rHiddenTarget.hidden then
                            table.insert(rStealthData.hidden, sText)
                        else
                            table.insert(rStealthData.visible, sText)
                        end
                    end

                    -- Check the aware/unaware, same text in each that will be rolled up in the output section below.
                    if nStealthSource ~= nil then
                        local sText = string.format("%s", sIterationActorDisplayName)
                        local sPPText = string.format(" - PP: %d", getPassivePerceptionNumber(rIterationActor))
                        local sConditionFormat = " - Condition: %s"
                        if doesTargetPerceiveAttackerFromStealth(nStealthSource, rIterationActor) then
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
    if EffectManager.hasEffect(nodeCreature, "ADVSKILL") then
        bADV = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "ADVSKILL", A_SKILL_FILTER)) > 0 then
        bADV = true
    elseif EffectManager.hasEffect(nodeCreature, "ADVCHK") then
        bADV = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "ADVCHK", A_CHECK_FILTER)) > 0 then
        bADV = true
    end
    if EffectManager.hasEffect(nodeCreature, "DISSKILL") then
        bDIS = true
    elseif #(EffectManager5E.getEffectsByType(nodeCreature, "DISSKILL", A_SKILL_FILTER)) > 0 then
        bDIS = true
    elseif EffectManager.hasEffect(nodeCreature, "DISCHK") then
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
    local nBonusStat, nBonusEffects = ActorManager5E.getAbilityEffectsBonus(nodeCreature, "wisdom")
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
    local sNodeType, nodeActor = ActorManager.getTypeAndNode(vActor);
    local nStatScore
    if sNodeType == "pc" then
        nStatScore = DB.getValue(nodeActor, "profbonus", 0);
    else
        nStatScore = getProficiencyBonusForNPCChallengeRating(nodeActor) or 0;
    end

    return nStatScore
end

function getProficiencyBonusForNPCChallengeRating(nodeActor)
    local sCR = DB.getValue(nodeActor, "cr", "")
    if sCR == "" then return 0 end

    if     sCR == "0"
        or sCR == "1/8"
        or sCR == "1/4"
        or sCR == "1/2"
        or sCR == "1"
        or sCR == "2"
        or sCR == "3"
        or sCR == "4" then
        return 2
    end

    if     sCR == "5"
        or sCR == "6"
        or sCR == "7"
        or sCR == "8" then
        return 3
    end

    if     sCR == "9"
        or sCR == "10"
        or sCR == "11"
        or sCR == "12" then
        return 4
    end

    if     sCR == "13"
        or sCR == "14"
        or sCR == "15"
        or sCR == "16" then
        return 5
    end

    if     sCR == "17"
        or sCR == "18"
        or sCR == "19"
        or sCR == "20" then
        return 6
    end

    if     sCR == "21"
        or sCR == "22"
        or sCR == "23"
        or sCR == "24" then
        return 7
    end

    if     sCR == "25"
        or sCR == "26"
        or sCR == "27"
        or sCR == "28" then
        return 8
    end

    if     sCR == "29"
        or sCR == "30" then
        return 9
    end

    return 0
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
	displayProcessAttackFromStealth(ActorManager.resolveActor(msgOOB.sSourceCTNode), ActorManager.resolveActor(msgOOB.sTargetCTNode))
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

    local sCooked = string.gsub(sTest, "$s+", "")
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
	local rTarget = ActorManager.resolveActor(nodename)
	onDropEvent(rSource, rTarget, draginfo)
	CombatManager_onDrop(nodetype, nodename, draginfo)
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
	ActionAttack_onAttack(rSource, rTarget, rRoll)

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
	ActionSkill_onRoll(rSource, rTarget, rRoll)
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
    CombatManager_requestActivation(nodeEntry, bSkipBell)
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
