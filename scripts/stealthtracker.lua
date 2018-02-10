--
-- © Copyright Justin Freitas 2018+ except where explicitly stated otherwise.
-- Fantasy Grounds is Copyright © 2004-2018 SmiteWorks USA LLC.
-- Copyright to other material within this file may be held by other Individuals and/or Entities.
-- Nothing in or from this LUA file in printed, electronic and/or any other form may be used, copied,
--	transmitted or otherwise manipulated in ANY way without the explicit written consent of
--	Justin Freitas or, where applicable, any and all other Copyright holders.
--

-- Limitation: NPC must have 'passive Perception X' in the 'senses' field, otherwise, 10+wis is used.

-- Global message type to allow the client to update a npc record on the host.
OOB_MSGTYPE_UPDATESTEALTH = "updatestealth"

-- This function is required for all extensions to initialize variables and spit out the copyright and name of the extension as it loads
function onInit()

	-- Prepare the launch message object
	local msg = {sender = "", font = "emotefont", icon = "stealth_icon"}
	-- Here we name our extension, copyright, and author (Lua handles most \ commands as per other string languages where \r is a carriage return.
	msg.text = "StealthTracker v1.2 for Fantasy Grounds v3.X, 5E" .. "\r" .. "Copyright 2016-18 Justin Freitas (2/7/18)"
	-- Register Extension Launch Message (This registers the launch message with the ChatManager.)
	ChatManager.registerLaunchMessage(msg)
	
	-- Only set up the extension functionality on the host machine because it has access/permission to all of the necessary data.
	if User.isHost() then
		-- Here is where we register the onTurnStartEvent. We can register many of these which is useful. It adds them to a list and iterates through them in the order they were added.
		CombatManager.setCustomTurnStart(onTurnStartEvent)
		-- We don't need onTurnEnd, although, it's available.  Was too late in the turn lifecycle to change the name of the following actor for chat turn announcement by the system.
		--CombatManager.setCustomTurnEnd(onTurnEndEvent)
		-- Instead, we were able to make that name change in the InitChange handler, which occurs earlier than TurnEnd.
		CombatManager.setCustomInitChange(onInitChangeEvent)
		-- This allows a hook for us to reset all of the CT actor names upon clearing of initiative/combat via CT menu.
		CombatManager.setCustomCombatReset(onCombatResetEvent)
		-- Register a handler for the updatestealth OOB message.
		OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_UPDATESTEALTH, handleUpdateStealth);
	end
	
	-- Unlike the Custom Turn and Init events above, the dice result handler must be registered on host and client.
	-- On extension init, override the skill result handler with ours and call the default when we are done with our work.
	ActionsManager.registerResultHandler("skill", onRoll)
	
	-- Set up the chat command for everyone, clients and host.
	Comm.registerSlashHandler("stealthtracker", processChatCommand)
	Comm.registerSlashHandler("st", processChatCommand)
end

function clearAllStealthTrackerDataFromNames()
	-- Sort by init, etc like in CombatManager.sortfuncStandard.
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	
	-- Walk the CT resetting all names.
	-- TODO: Walk the character list (in case they aren't in CT).
	-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the key).
	for _,nodeCT in pairs(lCombatTrackerActors) do
		local oActor = ActorManager.getActorFromCT(nodeCT)
		-- The creature node points to the character sheet for pc or the CT node for npc.
		local nodeCreature = DB.findNode(oActor['sCreatureNode'])
		if nodeCreature then
			local sOrigCreatureNodeName = DB.getText(nodeCreature, "name", "")
			DB.setValue(nodeCreature, "name", "string", removeStealthFromName(sOrigCreatureNodeName))
		end
	end
end

function displayLocalChatMessage(sMessage, bSecret)
	local msg = {font = "msgfont"}
	msg.icon = "stealth_icon"
	-- Finish creating the message (with text and secret flag), then post it to chat.
	msg.text = "StealthTracker - " .. sMessage
	msg.secret = bSecret
	-- IMPORTANT NOTE: deliverChatMessage() is a broadcast mechanism, addChatMessage() is local only.
	Comm.addChatMessage(msg)
end

-- This gets the Passive Perception number from the character sheet for pcs and ct node for npc.
-- This function can return nil.
function getPassivePerceptionNumber(rActor)
	if not rActor then return nil end
	
	local nPP
	local rCreatureNode = DB.findNode(rActor.sCreatureNode)
	
	-- If creature node wasn't fetched, display local error and return nil.
	if not rCreatureNode then
		displayLocalChatMessage("Error getting passive perception for: " .. rActor.sName, true)
		return nil
	end
	
	if rActor.sType == "pc" then
		-- For a PC it's the "perception" child node.
		-- The perception value is always populated and always a number type.
		local nodePerception = rCreatureNode.getChild("perception")
		if nodePerception then
			nPP = rCreatureNode.getChild("perception").getValue()
		end
	elseif rActor.sType == "npc" then
		local rSensesNode = rCreatureNode.getChild("senses")
		local sSensesValue, sPP
		if rSensesNode then
			sSensesValue = rSensesNode.getText()
			sPP = string.match(sSensesValue, "passive Perception (%-?%d+)")
		end
		if sPP then
			nPP = tonumber(sPP)
		end
	end
	
	-- Calculation of passive perception from the wisdom modifier is same for pc/npc and should be used as a last resort.
	if not nPP then
		-- If senses/passive Perception isn't available, calculate from 10 + wis.
		nPP = 10 + rCreatureNode.getChild("abilities").getChild("wisdom").getChild("bonus").getValue()
	end
	
	return nPP
end

-- Function that uses a regular expression match to find the stealth number at the end of a CT actor name.
function getStealthNumberFromName(sActorName)
	-- The expression accounts for a leading space, optional dash character, a possible negative sign on the number, and trailing space all anchored to the end of the line.
	local sActorStealth = string.match(sActorName, "%s*[%-%s]s(%-?%d+)%s*$")
	local nStealth
	if sActorStealth then
		nStealth = tonumber(sActorStealth)
	end

	return nStealth
end

-- Handler for the message to update stealth that comes from a client player who is controlling a shared npc and making a stealth roll (no permission to update npc CT actor on client)
function handleUpdateStealth(msgOOB)
	if msgOOB.type == OOB_MSGTYPE_UPDATESTEALTH then
		local nodeCT = DB.findNode(msgOOB.sCTNodeId)
		if nodeCT then
			setNodeNameWithStealthValue(nodeCT, msgOOB.nStealthTotal)
		end
	end
end

-- Function to notify the host of a stealth update request.  The arguments are the CT node identifier and the stealth total number.
function notifyUpdateStealth(sCTNodeId, nStealthTotal)
	if not sCTNodeId or not nStealthTotal then return end

	-- Setup the OOB message object, including the required type.
	local msgOOB = {};
	msgOOB.type = OOB_MSGTYPE_UPDATESTEALTH;
		
	msgOOB.sCTNodeId = sCTNodeId;
	msgOOB.nStealthTotal = nStealthTotal;

	Comm.deliverOOBMessage(msgOOB, "");
end

-- Fires when the initiative is cleared via the CT menu.  Wired up in onInit() for the host only.
function onCombatResetEvent()
	-- We are exiting initiative/combat, so clear all StealthTracker data from CT actors.
	clearAllStealthTrackerDataFromNames()
end

-- Fires when the initiative is passed from actor to actor (or at the start from nil to actor).  Wired up in onInit() for the host only.
function onInitChangeEvent(nodeOldCT, nodeNewCT)
	if not nodeNewCT then return end
	local sOrigCreatureNodeName = DB.getText(nodeNewCT, "name", "")
	-- Clear any stealth values from the name.  Do it here because onTurnStartEvent() is too late for the chat turn header text.
	DB.setValue(nodeNewCT, "name", "string", removeStealthFromName(sOrigCreatureNodeName))
end

-- NOTE: The roll handler runs on whatever system throws the dice, so it does run on the clients... unlike the way the CT events are wired up to the host only (in onInit()).
-- This is the handler that we wire up to override the default roll handler.  We can do our logic, then call the default handler, and finally finish up with more logic.
function onRoll(rSource, rTarget, rRoll)
	-- Check the arguments used in this function.  Only process stealth if both are populated.  Never return prior to calling the default handler from the ruleset (below, ActionSkill.onRoll(rSource, rTarget, rRoll))
	local bProcessStealth = rSource and rRoll and string.find(rRoll.sDesc, "", 1, "[SKILL] Stealth")
	local nodeCreature, nActiveCTVisible
	
	-- If we are processing stealth, update the roll display to remove any existing stealth info.
	if bProcessStealth then
		-- rSource.sName is the pc/npc name that is the source of the roll and is only used for display in the chat for that roll (doesn't affect CT or character sheet)
		rSource['sName'] = removeStealthFromName(rSource['sName'])
		
		-- For PCs, sCreatureNode is their character sheet node.  For NPCs, it's the CT node (i.e. same as sCTNode).  This is important because when the game loads, the CT node name for PCs is lost... it's reloaded from their character sheet node on initialization.  This isn't the case for NPCs, which retain their modified name on game load.
		-- Capture the creature node of the actor that made the die roll
		nodeCreature = DB.findNode(rSource['sCreatureNode'])
		if nodeCreature then
			nActiveCTVisible = DB.getValue(nodeCreature, "tokenvis", 1)
			
				-- Check to see if the current actor is a npc and not visible.  If so, make the roll as secret/tower.
			if rSource.sType == 'npc' then
				if nActiveCTVisible == 0 then
					rRoll.bSecret = true
					rRoll.bTower = true
				end
			end
		end
	end
	
	-- Call the default action that happens when a skill roll occurs in the ruleset.
	ActionSkill.onRoll(rSource, rTarget, rRoll)
	
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

	-- To alter the creature name record, the source must be in the CT, combat must be going (there must be an active CT node), the first dice must be present in the roll, and the dice roller must either the DM or the actor who is active in the CT.
	if rSource.sCTNode ~= '' and nodeActiveCT and rRoll.aDice[1] and (User.isHost() or sSourceCreatureNodeName == sActiveCTName) then
		-- Calculate the stealth roll so that it's available to put in the creature name.  After the default ActionSkill.onRoll() has been called (above), there will be only one dice and that will be one for adv/dis, etc.
		local nStealthTotal = rRoll.aDice[1].result + rRoll.nMod

		-- If the source of the roll is a npc sheet shared to a player, notify the host to update the stealth value.
		if rSource.sType == 'npc' and not User.isHost() then
			notifyUpdateStealth(rSource.sCTNode, nStealthTotal)
		else -- Everyone has permission to update their own node.
			-- The CT node and the character sheet node are different nodes.  Updating the name on the CT node only updates the CT and not their character sheet value.  The CT name for a PC cannot be edited manually in the CT.  You have to go into character sheet and edit the name field (add a space and remove the space).
			--DB.setValue(nodeCreature, "name", "string", removeStealthFromName(sSourceCreatureNodeName) .. ' - s' .. nStealthTotal)
			setNodeNameWithStealthValue(nodeCreature, nStealthTotal)
		end
	end
end

-- This function is one that the Combat Tracker calls if present at the start of a creatures turn.  Wired up in onInit() for the host only.
function onTurnStartEvent(nodeEntry)
	if not nodeEntry then return end
	
	-- Get visibility from current actor.
	local nCurrentActorVisible = DB.getValue(nodeEntry, "tokenvis", 1)

	local oCurrentActor = ActorManager.getActorFromCT(nodeEntry)
	if not oCurrentActor then return end
	
	local nActorPP = getPassivePerceptionNumber(oCurrentActor)
	if not nActorPP then return end
	
	-- Get the creature node for the current CT actor.  For PC it's the character sheet node.  For NPC it's CT node.
	local nodeCreature = DB.findNode(oCurrentActor.sCreatureNode)
	if not nodeCreature then return end
	
	-- If the current actor is a PC, use the PC name for output instead of the CT name.
	local sActorName = DB.getText(nodeCreature, "name", "")
	sActorName = DB.getText(nodeCreature, "name", "")

	-- Sort by init, etc like in CombatManager.sortfuncStandard.
	--local lCombatTrackerActors = DB.getChildren("combattracker.list")
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	
	-- For efficiency, create the message table outside of the for loop.
	local msg = {font = "msgfont"}
	msg.icon = "stealth_icon"

	-- NOTE: _ is used as a placeholder in Lua for unused variables (in this case, the key).
	for _,nodeCT in pairs(lCombatTrackerActors) do
		local oIterationActor = ActorManager.getActorFromCT(nodeCT)
		local nIterationActorVisible = DB.getValue(nodeCT, "tokenvis", 1)
		local nIterationActorStealth = getStealthNumberFromName(oIterationActor.sName)
		
		if (oCurrentActor.sName ~= oIterationActor.sName and  -- Current actor doesn't equal iteration actor (no need to report on the actors own visibility!).
			(nIterationActorStealth and nActorPP < nIterationActorStealth)) then  -- Stealth value exists and it's greater than actor's PP.
			-- Finish creating the message (with text and secret flag), then post it to chat.
			msg.text = string.format("'%s' DOES NOT PERCEIVE '%s' due to being hidden (pp=%d vs. stealth=%d).", sActorName, removeStealthFromName(oIterationActor.sName), nActorPP, nIterationActorStealth)
			-- Make the message GM only if this iteration's CT token isn't visible.
			-- If the actor being checked is a npc and not visible, make the chat entry secret.
			msg.secret = (oCurrentActor.sType == 'npc' and nCurrentActorVisible == 0) or nIterationActorVisible == 0
			Comm.deliverChatMessage(msg)
		end
	end
end

function processChatCommand(sCommand, sParams)
	-- Only allow administrative subcommands when run on the host/DM system.
	if User.isHost() then
		processHostOnlySubcommands(sParams)
	else
		processUserOnlySubcommands(sParams)
	end
end

function processHostOnlySubcommands(sSubcommand)
	-- Default/empty subcommand - What does the current CT actor not perceive?
	if sSubcommand == '' then
		--TODO: This is the default subcommand for the host (/st with no subcommand)
		return
	end
	
	-- Clear all stealth names from CT actors creature nodes.
	if sSubcommand == "clear" then
		clearAllStealthTrackerDataFromNames()
		
		-- Display host command messages as a secret.  Since it's a local msg, it's always local to the issuer.
		displayLocalChatMessage("clear command complete")

		return
	end
	
	-- If we've gotten this far, the subcommand is invalid.
	displayLocalChatMessage("Unrecognized subcommand: " .. sSubcommand)
end

function processUserOnlySubcommands(sSubcommand)
	-- Default/empty subcommand - What does the character(s) asking not perceive?  Might be multiple.
	if sSubcommand == '' then
		--TODO: This is the default subcommand for the client (/st with no subcommand).  Maybe who doesn't see me in a local message?
		return
	end
	
	-- If we've gotten this far, the subcommand is invalid.
	displayLocalChatMessage("Unrecognized subcommand: " .. sSubcommand)
end

-- Function to globally remove the pattern matching ' - s22 ', where the dash is optional.
function removeStealthFromName(sActorName)
	return string.gsub(sActorName, "%s*%-*%s*s%-?%d+%s*$", "")
end

-- Function to encapsulate the setting of the name with stealth value.
function setNodeNameWithStealthValue(node, nStealthTotal)
	if not node or not nStealthTotal then return end
	
	-- Get the original name and strip any stealth info from it.
	local sOrigName = DB.getText(node, "name", "")
	local sCleanName = removeStealthFromName(sOrigName)
	DB.setValue(node, "name", "string", sCleanName .. ' - s' .. nStealthTotal)
end