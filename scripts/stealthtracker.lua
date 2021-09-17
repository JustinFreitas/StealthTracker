--
-- (c) Copyright Justin Freitas 2021+ except where explicitly stated otherwise.
-- Fantasy Grounds is Copyright (c) 2004-2021 SmiteWorks USA LLC.
-- Copyright to other material within this file may be held by other Individuals and/or Entities.
-- Nothing in or from this LUA file in printed, electronic and/or any other form may be used, copied,
-- transmitted or otherwise manipulated in ANY way without the explicit written consent of
-- Justin Freitas or, where applicable, any and all other Copyright holders.
--

-- Global message type to allow the client to update a npc record on the host.
OOB_MSGTYPE_UPDATESTEALTH = "updatestealth"
-- Global message type to allow the client to attack from stealth on the host.
OOB_MSGTYPE_ATTACKFROMSTEALTH = "attackfromstealth"
-- StealthTracker icon identifier
STEALTH_TRACKER_ICON = "stealth_icon"

-- This function is required for all extensions to initialize variables and spit out the copyright and name of the extension as it loads
-- luacheck: ignore onInit
function onInit()
	-- Here we name our extension, copyright, and author (Lua handles most special characters as per other languages, where \r is a carriage return).
	local msg = { sender = "", font = "emotefont", icon = STEALTH_TRACKER_ICON }
	msg.text = "StealthTracker v2.8 for FGC/FGU v3.3.15+, 5E" .. "\r" .. "Copyright 2016-21 Justin Freitas (9/16/21)"
	ChatManager.registerLaunchMessage(msg)

	-- Register StealthTracker Options
	OptionsManager.registerOption2("STEALTHTRACKER_EXPIRE_EFFECT", false, "option_header_stealthtracker", "option_label_STEALTHTRACKER_EXPIRE_EFFECT", "option_entry_cycler",
		{ baselabel = "option_val_on", baseval = "on", labels = "option_val_off", values = "off", default = "on" })
	OptionsManager.registerOption2("STEALTHTRACKER_BROADCAST_INFO", false, "option_header_stealthtracker", "option_label_STEALTHTRACKER_BROADCAST_INFO", "option_entry_cycler",
		{ baselabel = "option_val_on", baseval = "on", labels = "option_val_off", values = "off", default = "off" })

	-- Only set up the Custom Turn, Combat Reset, Custom Drop, and OOB Message event handlers on the host machine because it has access/permission to all of the necessary data.
	if User.isHost() then
		-- Here is where we register the onTurnStartEvent. We can register many of these which is useful. It adds them to a list and iterates through them in the order they were added.
		CombatManager.setCustomTurnStart(onTurnStartEvent)
		-- This allows a hook for us to reset all of the CT actor names upon clearing of initiative/combat via CT menu.
		CombatManager.setCustomCombatReset(onCombatResetEvent)
		-- Drop onto CT hook.
		CombatManager.setCustomDrop(onDropEvent)
		-- Register a handler for the updatestealth OOB message.
		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_UPDATESTEALTH, handleUpdateStealth)
		-- Register a handler for the attackfromstealth OOB message.
		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_ATTACKFROMSTEALTH, handleAttackFromStealth)

		-- Register chat commands for host only.
		Comm.registerSlashHandler("stealthtracker", processChatCommand)
		Comm.registerSlashHandler("st", processChatCommand)
	end

	-- Unlike the Custom Turn and Init events above, the dice result handler must be registered on host and client.
	-- On extension init, override the skill, attack (also handles spell attack rolls), and castsave result handlers with ours and call the default when we are done with our work (in the override).
	-- The potential conflict has been mitigated by a chaining technique where we store the current action handler for use in our overridden handler.
	ActionSkill.onRollStealthTracker = ActionSkill.onRoll
	ActionSkill.onRoll = onRollSkill
	ActionsManager.registerResultHandler("skill", onRollSkill)
	ActionAttack.onAttackStealthTracker = ActionAttack.onAttack
	ActionAttack.onAttack = onRollAttack
	ActionsManager.registerResultHandler("attack", onRollAttack)
	ActionPower.onCastSaveStealthTracker = ActionPower.onCastSave
	ActionPower.onCastSave = onRollCastSave
	ActionsManager.registerResultHandler("castsave", onRollCastSave)
end

-- Alphebetical list of functions below (onInit() above was an exception)

-- Converts a boolean into a number.
function booleanToNumber(bValue)
	return bValue == true and 1 or bValue == false and 0
end

function checkBroadcastChatOption()
	local option = OptionsManager.getOption("STEALTHTRACKER_BROADCAST_INFO"):lower()
	return option == "on"
end

-- Function to check, for a given CT node, which CT actors are hidden from it.  The local boolean allows for the chat output to be local only (not broadcast).
function checkCTNodeForHiddenActors(nodeCTSource)
	if not nodeCTSource then return end

	local rCurrentActor = ActorManager.resolveActor(nodeCTSource)
	if not rCurrentActor or not rCurrentActor.sCreatureNode then return end

	-- Get the creature node for the current CT actor.  For PC it's the character sheet node.  For NPC it's CT node.
	local nodeCreature = DB.findNode(rCurrentActor.sCreatureNode)
	if not nodeCreature then return end

	-- getSortedCombatantList() returns the list ordered as-is in CT (sorted by the CombatManager.sortfuncDnD sort function loaded by the 5e ruleset)
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	if not lCombatTrackerActors then return end

	-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the key).
	for _,nodeCT in ipairs(lCombatTrackerActors) do
		local rIterationActor = ActorManager.resolveActor(nodeCT)
		-- Compare the CT node ID (unique) instead of the name to prevent duplicate friendly names causing problems.
		if rIterationActor and rCurrentActor.sCTNode ~= rIterationActor.sCTNode then  -- Current actor doesn't equal iteration actor (no need to report on the actors own visibility!).
			local rHiddenTarget = isTargetHiddenFromSource(rCurrentActor, rIterationActor)
			if rHiddenTarget then
				-- Finish creating the message (with text and secret flag), then post it to chat.
				local sText = string.format("'%s' DOES NOT PERCEIVE '%s' due to being hidden (pp=%d vs stealth=%d).",
											ActorManager.getDisplayName(rHiddenTarget.source),
											ActorManager.getDisplayName(rIterationActor),
											rHiddenTarget.sourcePP,
											rHiddenTarget.stealth)
				-- Make the message GM only if this iteration's CT token isn't visible.
				-- If the actor being checked is a npc and not visible, make the chat entry secret.
				local bSecret = (isNpc(rCurrentActor) and not isFriend(rCurrentActor)) or CombatManager.isCTHidden(nodeCT)
				displayChatMessage(sText, bSecret, not checkBroadcastChatOption())
			end
		end
	end
end

function checkExpireEffectOption()
	local option = OptionsManager.getOption("STEALTHTRACKER_EXPIRE_EFFECT"):lower()
	return option == "on"
end

-- Function that walks the CT nodes and deletes the stealth effects from them.
function clearAllStealthTrackerDataFromCT()
	-- Walk the CT resetting all names.
	local ctListChildren = DB.getChildren(CombatManager.CT_LIST)
	if not ctListChildren then return end

	-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the key).
	for _,nodeCT in pairs(ctListChildren) do
		deleteAllStealthEffects(nodeCT)
	end
end

-- Deletes all of the stealth effects for a CT node (no expiration warning because this is cleanup and not effect usage causing the deletion).
function deleteAllStealthEffects(nodeCT)
	if not nodeCT then return end

	local nodeCTEffects = DB.getChildren(nodeCT, "effects")
	if not nodeCTEffects then return end

	for _,nodeEffect in pairs(nodeCTEffects) do
		if getStealthValueFromEffectNode(nodeEffect) then
			nodeEffect.delete()
		end
	end
end

-- Puts a message in chat that is broadcast to everyone attached to the host (including the host).
function displayChatMessage(sFormattedText, bSecret, bLocal)
	if not sFormattedText then return end

	local msg = {font = "msgfont", icon = STEALTH_TRACKER_ICON, secret = bSecret, text = sFormattedText}

	-- IMPORTANT NOTE: deliverChatMessage() is a broadcast mechanism, addChatMessage() is local only.
	if bLocal then
		Comm.addChatMessage(msg)
	else
		Comm.deliverChatMessage(msg)
	end
end

-- Function to display as a local chat message (not broadcast) the potentially unaware targets of an attacker that is stealthing, which might mean the attacker could take advantage on the roll.
function displayUnawareCTTargetsWithFormatting(sSourceName, nStealthSource, aUnawareTargets)
	if not sSourceName or not nStealthSource or not aUnawareTargets or #aUnawareTargets == 0 then return end

	-- First, let's build a new table that has the strings as they are to be output in chat.
	local aUnawareActorNamesAndPP = {}
	for _, rActor in ipairs(aUnawareTargets) do
		if rActor then
			local nPPActor = getPassivePerceptionNumber(rActor)
			if nPPActor ~= nil then
				table.insert(aUnawareActorNamesAndPP, string.format("'%s' - Passive Perception: %d", ActorManager.getDisplayName(rActor), getPassivePerceptionNumber(rActor)))
			end
		end
	end

	local sChatMessage
	if #aUnawareActorNamesAndPP == 0 then
		sChatMessage = string.format("'%s' is stealthing (Stealth: %d) but everyone in the Combat Tracker sees them.",
										sSourceName,
										nStealthSource)
	else
		-- Now, let's display a summary message and append the output strings from above appended to the end.
		sChatMessage = string.format("'%s' is stealthing (Stealth: %d). The following Combat Tracker actors would not see the attack coming and grant advantage:\r\r%s",
										sSourceName,
										nStealthSource,
										table.concat(aUnawareActorNamesAndPP, "\r"))
	end

	displayChatMessage(sChatMessage, false, true)
end

function displayUnawareTargetsForCurrentCTActor()
	-- Get the stealth for the current actor.
	local nodeActiveCT = CombatManager.getActiveCT()
	if not nodeActiveCT then return end

	local rSource = ActorManager.resolveActor(nodeActiveCT)
	if not rSource then return end

	local nStealthSource = getStealthNumberFromEffects(nodeActiveCT)
	if not nStealthSource then return end

	local aUnawareTargets = getUnawareCTTargetsGivenSource(rSource)
	if #aUnawareTargets == 0 then
		displayChatMessage("Current CT actor is stealthing but no unaware targets found.", false, true)
		return
	end

	displayUnawareCTTargetsWithFormatting(ActorManager.getDisplayName(rSource), nStealthSource, aUnawareTargets)
end

-- Function to check if the target perceives the attacker under stealth, returning true if so and false if not.
function doesTargetPerceiveAttackerFromStealth(nAttackerStealth, rTarget)
	if not nAttackerStealth or not rTarget then return false end

	local nPPTarget = getPassivePerceptionNumber(rTarget)
	return nPPTarget ~= nil and nPPTarget >= nAttackerStealth
end

-- Function to expire the last found stealth effect in the CT node's effects table.  An explicit expiration is needed because the built-in expiration only works if the coded effect matches a known roll or action type (i.e. ATK:3 will expire on attack roll).
function expireStealthEffectOnCTNode(rActor)
	if not rActor or not rActor.sCTNode or rActor.sCTNode == "" then return end

	local nodeCT = DB.findNode(rActor.sCTNode)
	if not nodeCT then return end

	local aSortedCTNodes = getOrderedEffectsTableFromCTNode(nodeCT)
	if not aSortedCTNodes then return end
	local nodeLastEffectWithStealth

	-- Walk the effects in order so that the last one added is taken in case they are stacked.
	for _,nodeEffect in pairs(aSortedCTNodes) do
		local sExtractedStealth = getStealthValueFromEffectNode(nodeEffect)
		if sExtractedStealth then
			nodeLastEffectWithStealth = nodeEffect
		end
	end

	-- If a stealth node was found walking the list, expire the effect.
	if nodeLastEffectWithStealth then
		EffectManager.expireEffect(nodeCT, nodeLastEffectWithStealth, 0)
	end
end

-- For the provided CT node, get an ordered list (in order that they were added) of the effects on it.
function getOrderedEffectsTableFromCTNode(nodeCT)
	local aCTNodes = {}
	for _,nodeEffect in pairs(DB.getChildren(nodeCT, "effects")) do
		table.insert(aCTNodes, nodeEffect)
	end
	table.sort(aCTNodes, function (a, b) return a.getName() < b.getName() end)
	return aCTNodes
end

-- This gets the Passive Perception number from the character sheet for pcs and ct node for npc.
-- This function can return nil.
function getPassivePerceptionNumber(rActor)
	if not rActor then return nil end

	local nPP
	local rCreatureNode = DB.findNode(rActor.sCreatureNode)
	if not rCreatureNode then return nil end

	-- The perception is calculated from different shees for pc vs npc.
	if rActor.sType == "charsheet" or rActor.sType == "pc" then
		-- For a PC it's the perception child node.
		-- The perception value is always populated and always a number type.
		local nodePerception = rCreatureNode.getChild("perception")
		if nodePerception then
			nPP = nodePerception.getValue()
		end
	elseif isNpc(rActor) then
		-- Limitation: NPC must have 'passive Perception X' in the 'senses' field, otherwise, 10+wis is used.
		local rSensesNode = rCreatureNode.getChild("senses")
		local sSensesValue, sPP
		if rSensesNode then
			-- Let's do the comparison in lower case to add some resiliance to the matching. Normally, the P in Perception is capitalized.
			sSensesValue = rSensesNode.getText():lower()
			sPP = string.match(sSensesValue, "passive%s+perception%s+(%-?%d+)")
		end
		if sPP then
			nPP = tonumber(sPP)
		end
	end

	-- TODO: Include the Stealth proficiency for PCs (if available) for this calculation.
	-- Calculation of passive perception from the wisdom modifier is same for pc/npc and should be used as a last resort (for PCs/charsheet, it should use Perception Prof/Expertise if it's there).
	-- Lua note: When used as control expression, the only false values in Lua are false and nil. Everything else is evaluated as true value.
	if not nPP then
		-- If senses/passive Perception isn't available, calculate from 10 + wis.  This code assumes the 5E ruleset items utilized will be there.
		nPP = 10 + ActorManager5E.getAbilityBonus(rCreatureNode, "wisdom")
	end

	return nPP
end

-- Function that walks the effects for a given CT node and extracts the last 'Stealth: X' effect stealth value.
function getStealthNumberFromEffects(nodeCT)
	if not nodeCT then return end

	local nStealth
	local aSorted = getOrderedEffectsTableFromCTNode(nodeCT)

	-- Walk the effects in order so that the last one added is taken in case they are stacked.  If a duplicate Stealth effect is found, remove subsequent ones.
	for _,nodeEffect in pairs(aSorted) do
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
	for _, component in ipairs(aEffectComponents) do
		local sMatch = string.match(component, "^%s*stealth:%s*(%-?%d+)%s*$")
		if sMatch then
			sExtractedStealth = sMatch
		end
	end

	return sExtractedStealth
end

-- Function to build a table of Actors that are unaware of the stealthing attacker.
function getUnawareCTTargetsGivenSource(rSource)
	-- Extract the stealth number from the source, if available.  It's used later in this function at a couple spots.
	local nodeSourceCT = DB.findNode(rSource.sCTNode)
	local nStealthSource = getStealthNumberFromEffects(nodeSourceCT)
	local aUnawareTargets = {}
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	if not lCombatTrackerActors then return end

	-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the key).
	for _,nodeCT in ipairs(lCombatTrackerActors) do
		local rTarget = ActorManager.resolveActor(nodeCT)
		if not isTargetHiddenFromSource(rSource, rTarget) and not doesTargetPerceiveAttackerFromStealth(nStealthSource, rTarget) then
			table.insert(aUnawareTargets, rTarget)
		end
	end

	return aUnawareTargets
end

-- Handler for the message to do an attack from a position of stealth.
function handleAttackFromStealth(msgOOB)
	if not msgOOB or not msgOOB.type then return end

	if msgOOB.type == OOB_MSGTYPE_ATTACKFROMSTEALTH then
		-- Deserialize the number. Numbers are serialized as strings in the OOB msg.
		if not msgOOB.sSourceCTNode or not msgOOB.sTargetCTNode then return end

		local nodeSourceCT = DB.findNode(msgOOB.sSourceCTNode)
		if not nodeSourceCT then return end

		local rSource = ActorManager.resolveActor(nodeSourceCT)
		if not rSource then return end

		local rTarget = nil
		if msgOOB.sTargetCTNode ~= "" then
			local nodeTargetCT = DB.findNode(msgOOB.sTargetCTNode)
			rTarget = ActorManager.resolveActor(nodeTargetCT)
		end
		processAttackFromStealth(rSource, rTarget)
	end
end

-- Handler for the message to update stealth that comes from a client player who is controlling a shared npc and making a stealth roll (no permission to update npc CT actor on client)
function handleUpdateStealth(msgOOB)
	if not msgOOB or not msgOOB.type then return end

	if msgOOB.type == OOB_MSGTYPE_UPDATESTEALTH then
		if not msgOOB.nStealthTotal or not msgOOB.sCTNodeId or not msgOOB.user then return end
		-- Deserialize the number. Numbers are serialized as strings in the OOB msg.
		local nStealthTotal = tonumber(msgOOB.nStealthTotal)
		if not nStealthTotal then return end
		setNodeWithStealthValue(msgOOB.sCTNodeId, nStealthTotal, msgOOB.user)
	end
end

-- Checks to see if the roll description (or drag info data) is a dexterity check roll.
function isDexterityCheckRoll(sRollData)
	if not sRollData then return false end
	return string.find(sRollData, "[CHECK] Dexterity", 1, true)
end

-- Function that checks an actor record to see if it's a friend (faction).
function isFriend(rActor)
	if not rActor then return false end
	return ActorManager.getFaction(rActor) == "friend"
end

-- Function that check an actor record (i.e. from ActorManager.resolveActor(nodeCT)) to see if it's an npc.
function isNpc(rActor)
	if not rActor then return false end
	return rActor.sType == "npc"
end

-- Checks to see if the roll description (or drag info data) is a stealth skill roll.
function isStealthSkillRoll(sRollData)
	if not sRollData then return false end
	return string.find(sRollData, "[SKILL] Stealth", 1, true)
end

-- Function to process the condition of the source perceiving the target (source PP >= target stealth).  Returns a table representing the hidden actor otherwise, nil.
function isTargetHiddenFromSource(rSource, rTarget)
	if not rSource or not rTarget or not rTarget.sCTNode then return end

	-- If the target has a stealth value, compare the source's PP to it to see if the attacker perceives the hiding target.
	local rTargetCTNode = DB.findNode(rTarget.sCTNode)
	if not rTargetCTNode then return end
	local nStealthTarget = getStealthNumberFromEffects(rTargetCTNode)
	if nStealthTarget ~= nil then
		local nPPSource = getPassivePerceptionNumber(rSource)
		if nPPSource ~= nil and nPPSource < nStealthTarget then
			local rHiddenActor = {
				source = rSource,
				target = rTarget,
				stealth = nStealthTarget,
				sourcePP = nPPSource
			}

			return rHiddenActor
		end
	end

	return nil
end

-- Function to notify the host of a stealth update so that the host can update items with proper permissions.
function notifyAttackFromStealth(sSourceCTNode, sTargetCTNode)
	if not sSourceCTNode or not sTargetCTNode then return end

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
	if not sCTNodeId or not nStealthTotal then return end

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
	-- We are exiting initiative/combat, so clear all StealthTracker data from CT actors.
	clearAllStealthTrackerDataFromCT()
end

-- Fires with something is dropped on the CT
-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the rSource argument).
function onDropEvent(_, rTarget, draginfo)
	if not rTarget or not rTarget.sCreatureNode or not rTarget.sCTNode or not draginfo then return true end

	local sDragInfoData = draginfo.getStringData()
	if not sDragInfoData then return end
	-- If the dropped item was a stealth roll, update the target creature node with the stealth value.
	if isStealthSkillRoll(sDragInfoData) or isDexterityCheckRoll(sDragInfoData) then
		-- Use the creature node, that way if it's a PC, we get its owner.
		local rTargetCreatureNode = DB.findNode(rTarget.sCreatureNode)
		if not rTargetCreatureNode then return end
		local sTargetOwner = DB.getOwner(rTargetCreatureNode)
		if not sTargetOwner then return true end
		setNodeWithStealthValue(rTarget.sCTNode, draginfo.getNumberData(), sTargetOwner)
	end

	-- This is required, otherwise, the wired drop handler fires twice.  It terminates the default drop processing.
	return true
end

-- Attack roll handler
function onRollAttack(rSource, rTarget, rRoll)
	-- Call the stored (during initialization in onInit()) attack roll handler.
	ActionAttack.onAttackStealthTracker(rSource, rTarget, rRoll)
	processAttackFromStealth(rSource, rTarget)
end

function onRollCastSave(rSource, rTarget, rRoll)
	ActionPower.onCastSaveStealthTracker(rSource, rTarget, rRoll)
	-- TODO: Check attack possible due to sight?  Will require a processCastSaveFromStealth(), notifyCastSaveFromStealth(), and handleCastSaveFromStealth().
	expireStealthEffectOnCTNode(rSource)
end

-- NOTE: The roll handler runs on whatever system throws the dice, so it does run on the clients... unlike the way the CT events are wired up to the host only (in onInit()).
-- This is the handler that we wire up to override the default roll handler.  We can do our logic, then call the stored action handler (via onInit()), and finally finish up with more logic.
function onRollSkill(rSource, rTarget, rRoll)
	-- Check the arguments used in this function.  Only process stealth if both are populated.  Never return prior to calling the default handler from the ruleset (below, ActionSkill.onRollStealthTracker(rSource, rTarget, rRoll))
	-- TODO: Override the onRollCheck() handler to account for the possibility of a Dex check being used as a stealth roll (i.e. "[CHECK] Dexterity").  Allow this for NPC's without a Stealth skill only.
	local bProcessStealth = rSource and rSource.sCTNode and rSource.sType and rRoll and isStealthSkillRoll(rRoll.sDesc)
	local nodeCreature

	-- If we are processing stealth, update the roll display to remove any existing stealth info.
	if bProcessStealth then
		-- For PCs, sCreatureNode is their character sheet node.  For NPCs, it's the CT node (i.e. same as sCTNode).  This is important because when the game loads, the CT node name for PCs is lost... it's reloaded from their character sheet node on initialization.  This isn't the case for NPCs, which retain their modified name on game load.
		-- Capture the creature node of the actor that made the die roll
		nodeCreature = DB.findNode(rSource.sCTNode)
		-- Check to see if the current actor is a npc and not visible.  If so, make the roll as secret/tower.
		if nodeCreature and isNpc(rSource) and CombatManager.isCTHidden(nodeCreature) then
			rRoll.bSecret = true
		end
	end

	-- Call the default action that happens when a skill roll occurs in the ruleset.
	ActionSkill.onRollStealthTracker(rSource, rTarget, rRoll)

	-- If this isn't a Stealth roll, forgo StealthTracker processing.
	if not bProcessStealth then return end

	-- Get the node for the current CT actor.
	local nodeActiveCT = CombatManager.getActiveCT()
	-- If there was no active CT actor/node, forgo StealthTracker processing.
	if not nodeActiveCT then return end
	local sActiveCTName = DB.getText(nodeActiveCT, "name", "")

	-- If there was no creature node from the source, forgo StealthTracker processing.
	if not nodeCreature then return end
	local sSourceCreatureNodeName = DB.getText(nodeCreature, "name", "")

	-- To alter the creature effect, the source must be in the CT, combat must be going (there must be an active CT node), the first dice must be present in the roll, and the dice roller must either the DM or the actor who is active in the CT.
	if rSource.sCTNode ~= "" and nodeActiveCT and rRoll.aDice[1] and (User.isHost() or sSourceCreatureNodeName == sActiveCTName) then
		-- Calculate the stealth roll so that it's available to put in the creature effects.  After the default ActionSkill.onRollStealthTracker() has been called (above), there will be only one dice and that will be one for adv/dis, etc.
		local nStealthTotal = rRoll.aDice[1].result + rRoll.nMod

		-- If the source of the roll is a npc sheet shared to a player, notify the host to update the stealth value.
		if User.isHost() then
			-- The CT node and the character sheet node are different nodes.  Updating the name on the CT node only updates the CT and not their character sheet value.  The CT name for a PC cannot be edited manually in the CT.  You have to go into character sheet and edit the name field (add a space and remove the space).
			setNodeWithStealthValue(rSource.sCTNode, nStealthTotal)
		else
			notifyUpdateStealth(rSource.sCTNode, nStealthTotal)
		end
	end
end

-- This function is one that the Combat Tracker calls if present at the start of a creatures turn.  Wired up in onInit() for the host only.
function onTurnStartEvent(nodeEntry)
	-- Do the GM only display of the actors that are hidden to the current actor.
	checkCTNodeForHiddenActors(nodeEntry)
	-- Do the host-only (because this handler is wired for host only) local display of CT actors that might be caught off guard by a stealthing attacker.
	displayUnawareTargetsForCurrentCTActor()
end

-- Function to do the 'attack from stealth' comparison where the attacker could have advantage if the target doesn't perceive the attacker (chat msg displayed).
-- This is called from the host only.
function performAttackFromStealth(rSource, rTarget, nStealthSource)
	local sMsgText
	if not isTargetHiddenFromSource(rSource, rTarget) then
		if not doesTargetPerceiveAttackerFromStealth(nStealthSource, rTarget) then
			-- Warn the chat that the attacker is hidden from the target in case they can take advantage on the roll (i.e. roll the attack again).
			sMsgText = string.format(
										"Attacker is hidden from target. Should attack be at advantage? (Attacker '%s' Stealth: %d, Target '%s' Passive Perception: %d).",
										ActorManager.getDisplayName(rSource),
										nStealthSource,
										ActorManager.getDisplayName(rTarget),
										getPassivePerceptionNumber(rTarget)
									)
		else
			-- Target sees the attack coming.  Build appropriate message.
			sMsgText = string.format(
										"Target sees the attack coming, no advantage from stealth for attacker. (Target '%s' Passive Perception: %d, Attacker '%s' Stealth: %d)",
										ActorManager.getDisplayName(rTarget),
										getPassivePerceptionNumber(rTarget),
										ActorManager.getDisplayName(rSource),
										nStealthSource
									)
		end
	end

	if sMsgText then
		displayChatMessage(sMsgText, false, not checkBroadcastChatOption())
	end

	expireStealthEffectOnCTNode(rSource)
end

-- Logic to process an attack from stealth (for checking if enemies could have been attacked with advantage, etc).  It's call from BOTH an attack roll and a spell attack roll (i.e. cast and castattack).
function processAttackFromStealth(rSource, rTarget)
	-- If the source is nil but rTarget is present, that is a drag\drop from the chat to the CT for an attack roll. Problem is, there's no way to deduce who the source was.  Instead, let's assume it's the active CT node.
	if not rSource then
		local nodeActiveCT = CombatManager.getActiveCT()
		if not nodeActiveCT then return end
		rSource = ActorManager.resolveActor(nodeActiveCT)
	end

	-- if no source or no roll then exit, skipping StealthTracker processing.
	if not rSource or not rSource.sCTNode or rSource.sCTNode == "" then return end

	-- Extract the stealth number from the source, if available.  It's used later in this function at a couple spots.
	local nodeSourceCT = DB.findNode(rSource.sCTNode)
	local nStealthSource = getStealthNumberFromEffects(nodeSourceCT)

	if not User.isHost() then
		-- We'll have to marshal the attack from clients via OOB message because the client doesn't have access to the target information here (throws console error for nil/nPP)
		notifyAttackFromStealth(rSource.sCTNode, (rTarget and rTarget.sCTNode) or "", nStealthSource)
		return
	end

	-- HOST ONLY PROCESSING STARTS HERE ----------------------------------------------------------------------------------------------------------
	-- Do special StealthTracker handling if there was no target set.  After this special processing, exit/return.
	-- When there is no target, report the CT actors that are hidden from the source.
	if not rTarget then
		local aHiddenTargets = {}
		-- For each actor in the combat tracker, check to see if it is a viable target.
		-- getSortedCombatantList() returns the list ordered as-is in CT (sorted by the CombatManager.sortfuncDnD sort function loaded by the 5e ruleset)
		local lCombatTrackerActors = CombatManager.getSortedCombatantList()
		if not lCombatTrackerActors then return end
		-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the key).
		for _,nodeCT in ipairs(lCombatTrackerActors) do
			local rActor = ActorManager.resolveActor(nodeCT)
			if rActor and not CombatManager.isCTHidden(nodeCT) and rSource.sCTNode ~= rActor.sCTNode then
				local rHiddenTarget = isTargetHiddenFromSource(rSource, rActor)
				if rHiddenTarget then
					-- table.insert() will insert rActor into the table using the default integer 1's based key.
					table.insert(aHiddenTargets, rHiddenTarget)
				end
			end
		end

		-- If hidden targets were found, report on that fact in the chat.
		if #aHiddenTargets > 0 then
			--Build a table of hidden targets with their stealth values so that all of the results can be displayed in a single message instead of multiple.
			local aHiddenActorNamesAndStealth = {}
			local nSourcePP
			for _,rHiddenTarget in ipairs(aHiddenTargets) do
				table.insert(aHiddenActorNamesAndStealth, string.format("'%s' - Stealth: %d", ActorManager.getDisplayName(rHiddenTarget.target), rHiddenTarget.stealth))
				-- Only populate the nSourcePP once for use in the format msg (not is true only for nil & false... zero doesn't apply).
				if not nSourcePP then
					nSourcePP = rHiddenTarget.sourcePP
				end
			end
			local sChatMessage = string.format("An attack was made by '%s' that had no target. The following Combat Tracker actors are hidden from '%s', who has a Passive Perception of %d:\r\r%s",
											   ActorManager.getDisplayName(rSource),
											   ActorManager.getDisplayName(rSource),
											   nSourcePP,
											   table.concat(aHiddenActorNamesAndStealth, "\r"))
			displayChatMessage(sChatMessage, false, not checkBroadcastChatOption())
		end
	else -- if (not rTarget)
		-- If the target is hidden in the CT, do not perform stealth processing (doesn't make much sense processing the stealth for an attack on a hidden actor).
		if CombatManager.isCTHidden(rTarget.sCTNode) then return end

		-- Check to see if the source can perceive the target.
		local rHiddenTarget = isTargetHiddenFromSource(rSource, rTarget)
		if rHiddenTarget then
			-- Warn the chat that the target might be hidden
			local sMsgText = string.format("Target hidden from attacker. Should attack be possible? ('%s' Stealth: %d, '%s' Passive Perception: %d).",
											ActorManager.getDisplayName(rTarget),
											rHiddenTarget.stealth,
											ActorManager.getDisplayName(rSource),
											rHiddenTarget.sourcePP)
			displayChatMessage(sMsgText, false, not checkBroadcastChatOption())
		end

		-- If the attacker/source was hiding, then check to see if the target can see the attack coming by comparing that stealth to the target's PP.
		if nStealthSource then
			performAttackFromStealth(rSource, rTarget, nStealthSource)
		end
	end -- else

	-- Expire their stealth effect.
	expireStealthEffectOnCTNode(rSource)
end

-- Handler for the 'st' and 'stealthtracker' slash commands in chat.
-- luacheck: ignore sCommand
function processChatCommand(sCommand, sParams)
	if not sParams then return end
	local sFailedSubcommand
	-- Only allow administrative subcommands when run on the host/DM system.
	sFailedSubcommand = processHostOnlySubcommands(sParams)
	if sFailedSubcommand then
		displayChatMessage("Unrecognized subcommand: " .. sFailedSubcommand, false, true)
	end
end

-- Chat commands that are for host only
function processHostOnlySubcommands(sSubcommand)
	-- Default/empty subcommand - What does the current CT actor not perceive?
	if sSubcommand == "" then
		-- This is the default subcommand for the host (/st with no subcommand). It will give a local only display of the actors hidden from the active CT actor.
		-- Get the node for the current CT actor.
		local nodeActiveCT = CombatManager.getActiveCT()
		checkCTNodeForHiddenActors(nodeActiveCT)
		displayUnawareTargetsForCurrentCTActor()
		return
	end

	-- Clear all stealth names from CT actors creature nodes.
	if sSubcommand == "clear" then
		clearAllStealthTrackerDataFromCT()

		-- Display host command messages as a secret.  Since it's a local msg, it's always local to the issuer.
		displayChatMessage("clear command complete", false, true)
		return
	end

	-- Fallthrough/unrecognized subcommand
	return sSubcommand
end

-- Function to encapsulate the setting of the name with stealth value.
function setNodeWithStealthValue(sCTNode, nStealthTotal)
	if not sCTNode or not nStealthTotal then return end

	-- First, delete any existing Stealth effects on the CT node.
	local nodeCT = DB.findNode(sCTNode)
	deleteAllStealthEffects(nodeCT)

	-- Then, add a new effect with the provided stealth value and make it be by user so that he/she can delete it from the CT on their own, if necessary.
	-- NOTE: When using addEffect to set effects, you must use the sCTNode and NOT the sCreatureNode (no effects on PC character sheet like in CT).
	local sEffectName = string.format("Stealth: %d", nStealthTotal)
	local nCurrentActorInit = DB.getValue(nodeCT, "initresult", 0)
	local nEffectExpirationInit = nCurrentActorInit - .1 -- .1 because we want it to tick right after their turn.
	local nEffectDuration = 0 -- according to 5e, actor should remain hidden until they do something to become visible (i.e. attack).
	if checkExpireEffectOption() then -- but let the user override that via an option setting.
		nEffectDuration = 2  -- because the effect init we used is after the user's turn.
	end

	local rActor = ActorManager.resolveActor(nodeCT)
	if not rActor then return end

	local nEffectGMOnly = booleanToNumber(isNpc(rActor) and not isFriend(rActor))
	EffectManager.addEffect("", "", nodeCT, { sName = sEffectName, nInit = nEffectExpirationInit, nDuration = nEffectDuration, nGMOnly = nEffectGMOnly }, true)
end
