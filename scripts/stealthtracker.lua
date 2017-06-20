--
-- © Copyright Justin Freitas 2017+ except where explicitly stated otherwise.
-- Fantasy Grounds is Copyright © 2004-2017 SmiteWorks USA LLC.
-- Copyright to other material within this file may be held by other Individuals and/or Entities.
-- Nothing in or from this LUA file in printed, electronic and/or any other form may be used, copied,
--	transmitted or otherwise manipulated in ANY way without the explicit written consent of
--	Justin Freitas or, where applicable, any and all other Copyright holders.
--

-- Limitation: Only visible actors will know who sees them.  To overcome this, we would need to track global set of CT actors on every stealth roll.
-- TODO: Always put the hidden actors in the GM's token tooltip.
-- Limitation: NPC must have 'passive Perception X' in the 'senses' field.

function getPassivePerceptionNumber(rActor)
		if not rActor then return nil end
		
		local nPP
		local rCreatureNode = DB.findNode(rActor.sCreatureNode)
		if rActor.sType == "pc" then
			-- For a PC it's the "perception" child node.
			-- The perception value is always populated and always a number type.
			nPP = rCreatureNode.getChild("perception").getValue()
		elseif rActor.sType == "npc" then
			local rSensesNode = rCreatureNode.getChild("senses")
			local sSensesValue, sPP
			if rSensesNode then
				sSensesValue = rSensesNode.getValue()
				sPP = string.match(sSensesValue, "passive Perception (%-?%d+)")
			end
			if sPP then
				nPP = tonumber(sPP)
			else
				-- TODO: Mark this calculation for reporting purposes?
				-- If senses/passive Perception isn't available, calculate from 10 + wis.
				nPP = 10 + rCreatureNode.getChild("abilities").getChild("wisdom").getChild("bonus").getValue()
			end
		end
		
		return nPP
end

function getStealthNumber(sActorName)
	local sActorStealth = string.match(sActorName, "%ss(%-?%d+)%s*$")
	local nStealth
	if sActorStealth then
		nStealth = tonumber(sActorStealth)
	end

	return nStealth
end

-- This function is one that the Combat Tracker calls if present at the start of a creatures turn.
function onTurnStartEvent(nodeEntry)
	if not nodeEntry then return end

	local rActor = ActorManager.getActorFromCT(nodeEntry);
	if not rActor then return end
	
	local nActorPP = getPassivePerceptionNumber(rActor)
	if not nActorPP then return end

	-- Sort by init, etc like in CombatManager.sortfuncStandard.
	--local lCombatTrackerActors = DB.getChildren("combattracker.list")
	local lCombatTrackerActors = CombatManager.getSortedCombatantList()
	
	-- For efficiency, create the message table outside of the for loop.
	local msg = {font = "msgfont"}
	msg.icon = "stealth_icon"

	-- TODO: Build an array of the names that can't be perceived, then refactor into function.
	for _,v in pairs(lCombatTrackerActors) do
		local sType = ActorManager.getActorFromCT(v).sType  -- pc or npc
		local sName = DB.getValue(v, "name", "")
		local nVisible = DB.getValue(v, "tokenvis", 1)
		local nStealth = getStealthNumber(sName)
		
		if (rActor.sName ~= sName and  -- Current actor doesn't equal iteration actor.
			(nVisible == 1 or sType == "pc") and  -- Always for PCs, but only when token visible for npc.
			(nStealth and nActorPP < nStealth)) then  -- Stealth value exists and it's greater than actor's PP.
			
			-- Finish creating the message (with text and secret flag), then post it to chat.
			msg.text = string.format("Actor DOES NOT PERCEIVE '%s' due to being hidden (pp=%d vs. stealth=%d).", sName, nActorPP, nStealth)
			-- Make the message GM only if the current actor is a NPC and it's token isn't visible.
			msg.secret = (rActor.sType == "npc" and DB.getValue(nodeEntry, "tokenvis", 1) == 0)
			Comm.deliverChatMessage(msg)
		end
	end
end

-- This function is required for all extensions to initialize variables and spit out the copyright and name of the extension as it loads
function onInit()
	local msg = {sender = "", font = "emotefont", icon = "stealth_icon"};
	-- Here we name our extension, copyright, and author (Lua handles most \ commands as per other string languages where \r is a carriage return.
	msg.text = "StealthTracker v1.0 for Fantasy Grounds v3.X, 5E" .. "\r" .. "Copyright 2017 Justin Freitas"
	-- Register Extension Launch Message (This registers the launch message with the ChatManager.)
	ChatManager.registerLaunchMessage(msg);
	
	-- Only set up the extension functionality on the host machine because it has access/permission to all of the necessary data.
	if User.isHost() then
		-- Here is where we register the onTurnStartEvent. We can register many of these which is useful. It adds them to a list and iterates through them in the order they were added.
		CombatManager.setCustomTurnStart(onTurnStartEvent);
	end
end