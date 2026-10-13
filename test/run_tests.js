const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { LuaFactory } = require('wasmoon');

async function runTests() {
    console.log("Setting up Lua VM via wasmoon...");
    const luaFactory = new LuaFactory();
    const lua = await luaFactory.createEngine();

    // 1. Mock the FGU Global Environment in the Lua State (5E Ruleset Mocks)
    console.log("Mocking FGU 5E environment globals...");
    
    await lua.doString(`
        ActorManager = {}
        ActorManager5E = {}
        DB = {}
        OptionsManager = {}
        Comm = {}
        Interface = {}
        User = {}
        ActionsManager = {}
        ActionD20 = {}
        EffectManager = {}
        EffectManager5E = {}
        OOBManager = {}
        StringManager = {}
        Debug = { console = function() end }

        function ActionsManager.total(rRoll)
            local nSum = (rRoll and rRoll.nMod) or 0
            if rRoll and rRoll.aDice then
                for _, d in ipairs(rRoll.aDice) do
                    nSum = nSum + (d.result or 0)
                end
            end
            return nSum
        end

        -- Mock StringManager
        function StringManager.isBlank(s)
            return s == nil or s == "" or s:gsub("%s+", "") == ""
        end

        function StringManager.trim(s)
            if not s then return "" end
            return (s:gsub("^%s*(.-)%s*$", "%1"))
        end

        -- Helper to create a mock databasenode
        function createMockNode(data)
            local node = {}
            node.data = data or {}
            
            function node.getPath() return "mock.path" end
            function node.getName() return "mockname" end
            
            function node.getChild(path)
                local val = node.data
                for part in string.gmatch(path, "[^%.]+") do
                    if type(val) == "table" then
                        val = val[part]
                    else
                        return nil
                    end
                end
                
                if val == nil then return nil end
                if type(val) == "table" then
                    return createMockNode(val)
                else
                    local leaf = {}
                    function leaf.getType() return type(val) == "number" and "number" or "string" end
                    function leaf.getValue() return val end
                    function leaf.getText() return val end
                    return leaf
                end
            end
            
            function node.getType() return "node" end
            function node.getChildren()
                local children = {}
                for k, v in pairs(node.data) do
                    if type(v) == "table" then
                        children[k] = createMockNode(v)
                    else
                        local leaf = {}
                        function leaf.getType() return type(v) == "number" and "number" or "string" end
                        function leaf.getValue() return v end
                        function leaf.getText() return v end
                        children[k] = leaf
                    end
                end
                return children
            end
            
            return node
        end

        -- Mock ActorManager APIs
        function ActorManager.getCreatureNode(v) return v end
        function ActorManager.getActor(v) return v end
        function ActorManager.resolveActor(v)
            if type(v) == "table" and v.getPath and not v.sCTNode then
                v.sCTNode = v.getPath()
            end
            return v
        end
        function ActorManager.isPC(v)
            if type(v) == "table" and type(v.getChild) == "function" then
                local nodeType = v.getChild("recordType")
                if nodeType then return nodeType.getValue() == "pc" end
            end
            if type(v) == "table" and v.recordType then return v.recordType == "pc" end
            return true
        end
        function ActorManager.getRecordType(v)
            if type(v) == "table" and type(v.getChild) == "function" then
                local nodeType = v.getChild("recordType")
                if nodeType then return nodeType.getValue() end
            end
            if type(v) == "table" and v.recordType then return v.recordType end
            return "pc"
        end
        function ActorManager.getCTNode(v) return v end
        function ActorManager.getFaction(v)
            if type(v) == "table" and type(v.getChild) == "function" then
                local nodeFaction = v.getChild("faction")
                if nodeFaction then return nodeFaction.getValue() end
            end
            if type(v) == "table" and v.faction then return v.faction end
            return "friend"
        end
        function ActorManager.getDisplayName(v) return v.displayName or "MockActor" end

        -- Mock ActorManager5E (Wisdom Modifier check)
        function ActorManager5E.getAbilityBonus(node, ability)
            if type(node) == "table" and type(node.getChild) == "function" then
                local val = node.getChild("abilities." .. ability .. ".bonus")
                if val then return val.getValue() end
            end
            if type(node) == "table" and node.abilities and node.abilities[ability] then
                return node.abilities[ability].bonus or 0
            end
            return 0
        end

        -- Mock DB APIs
        function DB.getValue(node, path, default)
            if type(node) == "table" and type(node.getChild) == "function" then
                local child = node.getChild(path)
                if child then return child.getValue() end
            end
            if type(node) == "table" and node[path] ~= nil then
                return node[path]
            end
            return default
        end
        
        function DB.getText(node, path, default)
            return DB.getValue(node, path, default) or ""
        end

        function DB.getChildren(node, path)
            if type(node) == "table" and type(node.getChild) == "function" then
                local childNode = node.getChild(path)
                if childNode and type(childNode.getChildren) == "function" then
                    return childNode.getChildren()
                end
            end
            if type(node) == "table" and path and node[path] then
                if type(node[path]) == "table" then
                    local res = {}
                    for k, v in pairs(node[path]) do
                        if type(v) == "table" and type(v.getChild) == "function" then
                            res[k] = v
                        else
                            res[k] = createMockNode(type(v) == "table" and v or { val = v })
                        end
                    end
                    return res
                end
            end
            return {}
        end

        function DB.setValue(node, path, typeStr, val)
            if type(node) == "table" and type(node.getChild) == "function" then
                if node.data then
                    node.data[path] = val
                end
            elseif type(node) == "table" then
                node[path] = val
            end
        end

        function DB.deleteNode(node)
            if type(node) == "table" and type(node.delete) == "function" then
                node.delete()
            end
        end

        -- Mock OptionsManager
        OptionsManager_mock_options = {}
        function OptionsManager.getOption(key) return OptionsManager_mock_options[key] or "off" end
        function OptionsManager.isOption(key, val) return OptionsManager_mock_options[key] == val end

        -- Mock EffectManager hasEffect to avoid nil calls
        function EffectManager.hasEffect(rActor, sEffect)
            if type(rActor) == "table" then
                local nodeData = rActor.data or rActor
                if nodeData.effects then
                    for _, eff in ipairs(nodeData.effects) do
                        if eff == sEffect then return true end
                    end
                end
            end
            return false
        end
        function EffectManager.getEffectsByType() return {} end
        function EffectManager.expireEffect(nodeCT, nodeEffect, nExpireComp)
            if nodeEffect and nodeEffect.delete then
                nodeEffect.delete()
            end
            return true
        end
        
        -- Mock register callbacks to avoid crashes on load
        function ActionsManager.registerResultHandler() end
        function ActionsManager.registerPostRollHandler() end
        function OOBManager.registerOOBMsgHandler() end
        function Comm.registerSlashHandler() end
    `);

    // 2. Load the actual 5E StealthTracker script
    console.log("Loading scripts/stealthtracker.lua into VM...");
    const luaCodePath = path.join(__dirname, '../scripts/stealthtracker.lua');
    const luaCode = fs.readFileSync(luaCodePath, 'utf8');
    
    await lua.doString(luaCode);
    console.log("StealthTracker loaded successfully inside VM.\n");

    // 3. Define and run test assertions
    console.log("Running Unit Tests...");
    let testsPassed = 0;
    let testsFailed = 0;

    function runAssert(fnName, expected, luaCodeToRun) {
        try {
            const result = lua.doStringSync(luaCodeToRun);
            assert.strictEqual(result, expected);
            console.log(`  ✓ PASS: ${fnName} -> got ${result}`);
            testsPassed++;
        } catch (err) {
            console.error(`  ✗ FAIL: ${fnName} -> expected ${expected}, got error or mismatch:\n`, err);
            testsFailed++;
        }
    }

    // --- GROUP A: Core Math & Conversions ---
    await runAssert("booleanToNumber(true)", 1, "return booleanToNumber(true)");
    await runAssert("booleanToNumber(false)", 0, "return booleanToNumber(false)");

    // --- GROUP B: Settings & Flags ---
    await runAssert("checkAllowOutOfCombat() default", false, "return checkAllowOutOfCombat()");
    await lua.doString(`OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "all"`);
    await runAssert("checkAllowOutOfCombat() enabled", true, "return checkAllowOutOfCombat()");
    await lua.doString(`OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "off"`);

    // --- GROUP C: Roll Type Identification ---
    await runAssert("isStealthSkillRoll('[skill] stealth')", "[skill] stealth", "return isStealthSkillRoll('[skill] stealth')");
    await runAssert("isStealthSkillRoll('Perception')", null, "return isStealthSkillRoll('Perception')");
    
    await runAssert("isDexterityCheckRoll('[check] dexterity')", "[check] dexterity", "return isDexterityCheckRoll('[check] dexterity')");
    await runAssert("isDexterityCheckRoll('Strength')", null, "return isDexterityCheckRoll('Strength')");

    // --- GROUP D: Character / Actor Checks ---
    await lua.doString(`
        mockPC = createMockNode({ recordType = "pc", faction = "friend" })
        mockNPC = createMockNode({ recordType = "npc", faction = "foe" })
    `);
    await runAssert("isNpc(mockNPC)", true, "return isNpc(mockNPC)");
    await runAssert("isNpc(mockPC)", false, "return isNpc(mockPC)");
    
    await runAssert("isFriend(mockPC)", true, "return isFriend(mockPC)");
    await runAssert("isFriend(mockNPC)", false, "return isFriend(mockNPC)");

    await runAssert("isDifferentFaction(mockPC, mockNPC)", true, "return isDifferentFaction(mockPC, mockNPC)");
    await runAssert("isDifferentFaction(mockPC, mockPC)", false, "return isDifferentFaction(mockPC, mockPC)");

    // --- GROUP E: Unidentified NPC Names ---
    await lua.doString(`
        nodeUnidentified = createMockNode({
            recordType = "npc",
            isidentified = 0,
            nonid_name = "Scary Goblin"
        })
        nodeIdentified = createMockNode({
            recordType = "npc",
            isidentified = 1,
            nonid_name = "Scary Goblin"
        })
    `);
    await runAssert("isUnidentifiedNpc(nodeUnidentified)", true, "return isUnidentifiedNpc(nodeUnidentified)");
    await runAssert("isUnidentifiedNpc(nodeIdentified)", false, "return isUnidentifiedNpc(nodeIdentified)");
    await runAssert("getUnidentifiedName(nodeUnidentified)", "Scary Goblin", "return getUnidentifiedName(nodeUnidentified)");

    // --- GROUP F: Effect Exclusions & Stealth values ---
    await lua.doString(`
        -- Mock EffectManager helper
        EffectManager.parseEffect = function(label) return { label } end
    `);
    await runAssert(
        "getStealthValueFromEffectNode-parsing-variations",
        true,
        `
            local val1 = getStealthValueFromEffectNode(createMockNode({ label = "Stealth: 14" }))
            local val2 = getStealthValueFromEffectNode(createMockNode({ label = "(Stealth: 14)" }))
            local val3 = getStealthValueFromEffectNode(createMockNode({ label = " (Stealth: 14) " }))
            local val4 = getStealthValueFromEffectNode(createMockNode({ label = "ATK: +2" }))
            return val1 == "14" and val2 == "14" and val3 == "14" and val4 == nil
        `
    );

    // --- GROUP G: Passive Perception Math (5E Ruleset) ---
    // PC Case: Read directly from "perception" field on the character sheet
    await lua.doString(`
        mockPCNode = createMockNode({
            recordType = "pc",
            perception = 14
        })
    `);
    await runAssert("getPassivePerceptionNumber(mockPC) PC", 14, "return getPassivePerceptionNumber(mockPCNode)");

    // NPC Case A: Read from "senses" text field (e.g. passive Perception 12)
    await lua.doString(`
        mockNPCNodeA = createMockNode({
            recordType = "npc",
            senses = "Darkvision 60 ft., passive Perception 12"
        })
    `);
    await runAssert("getPassivePerceptionNumber(mockNPC) with senses", 12, "return getPassivePerceptionNumber(mockNPCNodeA)");

    // NPC Case B: Fallback calculation (10 + Wisdom Modifier)
    await lua.doString(`
        mockNPCNodeB = createMockNode({
            recordType = "npc",
            senses = "",
            abilities = {
                wisdom = {
                    bonus = 3
                }
            }
        })
    `);
    // Calculation: 10 + Wisdom Mod 3 = 13
    await runAssert("getPassivePerceptionNumber(mockNPC) fallback", 13, "return getPassivePerceptionNumber(mockNPCNodeB)");

    // --- GROUP H: Combat Tracker Node Validity ---
    await lua.doString(`
        nodeValidPC = createMockNode({ type = "Beast", faction = "friend" })
        nodeValidNPC = createMockNode({ type = "Monstrosity", faction = "foe" })
        nodeInvalidType = createMockNode({ type = "trap", faction = "neutral" })
    `);
    await runAssert("isValidCTNode(nodeValidPC)", true, "return isValidCTNode(nodeValidPC)");
    await runAssert("isValidCTNode(nodeValidNPC)", true, "return isValidCTNode(nodeValidNPC)");
    await runAssert("isValidCTNode(nodeInvalidType)", false, "return isValidCTNode(nodeInvalidType)");

    // --- GROUP I: doesTargetPerceiveAttackerFromStealth (Condition Coverage) ---
    await lua.doString(`
        mockTarget = mockPCNode -- PP is 14
    `);
    // Case 1: Attacker Stealth is 13 (lower than target perception 14) -> returns true (spotted)
    await runAssert("doesTargetPerceiveAttackerFromStealth(13) [spotted]", true, "return doesTargetPerceiveAttackerFromStealth(13, mockTarget)");
    // Case 2: Attacker Stealth is 14 (equal to target perception 14) -> returns true (spotted)
    await runAssert("doesTargetPerceiveAttackerFromStealth(14) [spotted]", true, "return doesTargetPerceiveAttackerFromStealth(14, mockTarget)");
    // Case 3: Attacker Stealth is 15 (higher than target perception 14) -> returns false (hidden)
    await runAssert("doesTargetPerceiveAttackerFromStealth(15) [hidden]", false, "return doesTargetPerceiveAttackerFromStealth(15, mockTarget)");

    // --- GROUP J: getActorDebilitatingCondition (Condition Coverage) ---
    await lua.doString(`
        actorDead = createMockNode({ recordType = "npc", effects = { "unconscious" } })
        actorStunned = createMockNode({ recordType = "npc", effects = { "stunned" } })
        actorParalyzed = createMockNode({ recordType = "npc", effects = { "paralyzed" } })
        actorHealthy = createMockNode({ recordType = "npc", effects = {} })
    `);
    await runAssert("getActorDebilitatingCondition(unconscious)", "unconscious", "return getActorDebilitatingCondition(actorDead)");
    await runAssert("getActorDebilitatingCondition(stunned)", "stunned", "return getActorDebilitatingCondition(actorStunned)");
    await runAssert("getActorDebilitatingCondition(paralyzed)", "paralyzed", "return getActorDebilitatingCondition(actorParalyzed)");
    await runAssert("getActorDebilitatingCondition(healthy)", null, "return getActorDebilitatingCondition(actorHealthy)");

    // --- GROUP K: isStealthTrackerDisabledForActor (Condition Coverage) ---
    await lua.doString(`
        actorDisabled = createMockNode({ senses = "No StealthTracker, Darkvision" })
        actorEnabledSenses = createMockNode({ senses = "Darkvision 60ft" })
    `);
    await runAssert("isStealthTrackerDisabledForActor(disabled)", "no stealthtracker", "return isStealthTrackerDisabledForActor(actorDisabled)");
    await runAssert("isStealthTrackerDisabledForActor(enabled)", null, "return isStealthTrackerDisabledForActor(actorEnabledSenses)");

    // --- GROUP L: isValidCTNode with Disabled Senses/Notes/Desc (Condition Coverage) ---
    await lua.doString(`
        actorPCDisabled = createMockNode({ type = "Beast", senses = "No StealthTracker" })
        actorNPCDisabled = createMockNode({ type = "Monstrosity", senses = "No StealthTracker" })
    `);
    await runAssert("isValidCTNode(PC disabled)", false, "return isValidCTNode(actorPCDisabled)");
    await runAssert("isValidCTNode(NPC disabled)", false, "return isValidCTNode(actorNPCDisabled)");

    // --- GROUP M: Observer Architecture & XML Escaping (v1.0.5 Backport) ---
    await lua.doString(`
        -- Define additional mocks required for onInit and observer testing
        function Interface.getString(s)
            if s == "skill_value_stealth" then return "Stealth" end
            if s == "dexterity" then return "Dexterity" end
            return s or ""
        end
        function User.isHost() return true end
        function OptionsManager.registerOption2() end
        
        CombatManager = {}
        function CombatManager.setCustomCombatReset() end
        function CombatManager.onDrop() end
        function CombatManager.requestActivation() end
        function CombatManager.getActiveCT() return nil end
        function CombatManager.getSortedCombatantList() return {} end
        function CombatManager.isCTHidden() return false end

        -- Backing table for ActionsManager handlers to test fallback
        ActionsManager.aHandlers = {}
        function ActionsManager.registerResultHandler(sType, fn)
            ActionsManager.aHandlers[sType] = fn
        end
        function ActionsManager.getResultHandler(sType)
            return ActionsManager.aHandlers[sType]
        end
        function ActionsManager.doesRollHaveDice(rRoll)
            return true
        end
        function ActionsManager.decodeActors(draginfo)
            return nil
        end

        -- Mock ruleset original result handlers
        nRulesetSkillCalls = 0
        nRulesetAttackCalls = 0
        function mockRulesetOnSkillRoll() nRulesetSkillCalls = nRulesetSkillCalls + 1 end
        function mockRulesetOnAttackRoll() nRulesetAttackCalls = nRulesetAttackCalls + 1 end
        ActionsManager.registerResultHandler("skill", mockRulesetOnSkillRoll)
        ActionsManager.registerResultHandler("attack", mockRulesetOnAttackRoll)

        -- Execute onInit to install observers/wrappers
        onInit()
    `);

    await runAssert(
        "observers-installed-via-ActionsManager",
        true,
        `
            return type(ActionsManager.getResultHandler("skill")) == "function"
               and type(ActionsManager.getResultHandler("attack")) == "function"
               and ActionsManager.getResultHandler("skill") ~= mockRulesetOnSkillRoll
               and ActionsManager.getResultHandler("attack") ~= mockRulesetOnAttackRoll
        `
    );

    await runAssert(
        "ruleset-handlers-chained-by-wrapper",
        true,
        `
            local nPrevSkill = nRulesetSkillCalls
            local nPrevAttack = nRulesetAttackCalls
            local fSkill = ActionsManager.getResultHandler("skill")
            local fAttack = ActionsManager.getResultHandler("attack")
            local rSource = createMockNode({ recordType = "pc" })
            fSkill(rSource, nil, { sType = "skill", sDesc = "[skill] perception" })
            fAttack(rSource, nil, { sType = "attack" })
            return (nRulesetSkillCalls == nPrevSkill + 1) and (nRulesetAttackCalls == nPrevAttack + 1)
        `
    );

    await runAssert(
        "double-init-is-noop (idempotent init guard)",
        true,
        `
            local fBeforeSkill = ActionsManager.getResultHandler("skill")
            local fBeforeAttack = ActionsManager.getResultHandler("attack")
            onInit()
            return fBeforeSkill == ActionsManager.getResultHandler("skill")
               and fBeforeAttack == ActionsManager.getResultHandler("attack")
        `
    );

    await runAssert(
        "onRollAttack observer routing",
        1,
        `
            local nAttackObserved = 0
            local fRealDisplay = displayProcessAttackFromStealth
            displayProcessAttackFromStealth = function() nAttackObserved = nAttackObserved + 1 end

            local fAttackSlot = ActionsManager.getResultHandler("attack")
            local rSource = createMockNode({ recordType = "pc" })
            local ok, err = pcall(fAttackSlot, rSource, nil, { sType = "attack" })

            displayProcessAttackFromStealth = fRealDisplay
            if not ok then error(err) end
            return nAttackObserved
        `
    );

    await runAssert(
        "onRollSkill observer routing",
        1,
        `
            local nSkillObserved = 0
            local fRealDisplay = displayProcessStealthUpdateForSkillHandlers
            displayProcessStealthUpdateForSkillHandlers = function() nSkillObserved = nSkillObserved + 1 end

            local fSkillSlot = ActionsManager.getResultHandler("skill")
            local rSource = createMockNode({ recordType = "pc" })
            local ok, err = pcall(fSkillSlot, rSource, nil, { sType = "skill", sDesc = "[skill] stealth", aDice = { { type = "d20", result = 15 } } })

            displayProcessStealthUpdateForSkillHandlers = fRealDisplay
            if not ok then error(err) end
            return nSkillObserved
        `
    );

    await lua.doString(`
        -- Test displayChatMessage XML escaping and mode cleanup
        lastChatMessage = nil
        Comm.addChatMessage = function(msg) lastChatMessage = msg end
    `);

    await runAssert(
        "chat-escapes-lt",
        "a &lt; b",
        `
            OptionsManager_mock_options["STEALTHTRACKER_FRAME_STYLE"] = "none"
            displayChatMessage("a < b", true)
            return lastChatMessage and lastChatMessage.text
        `
    );

    await runAssert(
        "chat-omits-empty-mode",
        null,
        `
            return lastChatMessage and lastChatMessage.mode
        `
    );

    await runAssert(
        "chat-sets-chosen-mode",
        "story",
        `
            OptionsManager_mock_options["STEALTHTRACKER_FRAME_STYLE"] = "story"
            displayChatMessage("hello", true)
            return lastChatMessage and lastChatMessage.mode
        `
    );

    await runAssert(
        "duplicate-actor-redirection-and-targeting",
        true,
        `
            ActorManager.node1 = {
                getPath = function() return "combattracker.list.id-00001" end
            }
            ActorManager.node3 = {
                getPath = function() return "combattracker.list.id-00003" end
            }
            ActorManager.node4 = {
                getPath = function() return "combattracker.list.id-00004" end
            }
            ActorManager.creatureNode = {
                getPath = function() return "charsheet.id-00001" end
            }
            ActorManager.rTargetMock = {
                sCTNode = "combattracker.list.id-00005"
            }
            
            local fRealGetCTNode = ActorManager.getCTNode
            local fRealGetActiveCT = CombatManager.getActiveCT
            local fRealGetCreatureNode = ActorManager.getCreatureNode
            local fRealGetFullTargets = TargetingManager and TargetingManager.getFullTargets
            local fRealDisplay = displayProcessAttackFromStealth
            local fRealGetDisplayName = ActorManager.getDisplayName
            local fRealGetSortedCombatantList = CombatManager.getSortedCombatantList
            local fRealGetStealthNumberFromEffects = getStealthNumberFromEffects
            local fRealResolveActor = ActorManager.resolveActor

            function ActorManager.getCTNode(s)
                if s == "combattracker.list.id-00001" then return ActorManager.node1 end
                if s == "combattracker.list.id-00004" then return ActorManager.node4 end
                if s == "combattracker.list.id-00003" then return ActorManager.node3 end
                if type(s) == "table" then
                    if s.sCTNode == "combattracker.list.id-00001" or s == ActorManager.node1 then return ActorManager.node1 end
                    if s.sCTNode == "combattracker.list.id-00003" or s == ActorManager.node3 then return ActorManager.node3 end
                    if s.sCTNode == "combattracker.list.id-00004" or s == ActorManager.node4 then return ActorManager.node4 end
                end
                return nil
            end
            function CombatManager.getActiveCT()
                return ActorManager.node4
            end
            function ActorManager.getCreatureNode(node)
                if node == ActorManager.node1 or node == ActorManager.node4 then
                    return ActorManager.creatureNode
                end
                return nil
            end
            function ActorManager.getDisplayName(r)
                if r == ActorManager.node3 or (type(r) == "table" and r.sCTNode == "combattracker.list.id-00003") then return "Durin Stonefist" end
                if r == ActorManager.node4 or (type(r) == "table" and r.sCTNode == "combattracker.list.id-00004") then return "Durin Stonefist" end
                return ""
            end
            
            TargetingManager = TargetingManager or {}
            function TargetingManager.getFullTargets(rSource)
                if rSource.sCTNode == "combattracker.list.id-00004" then
                    return { ActorManager.rTargetMock }
                end
                if rSource.sCTNode == "combattracker.list.id-00002" then
                    return { ActorManager.node4 }
                end
                return {}
            end

            -- Scenario 1: Verify getActiveDuplicateCTNodePath redirection
            local path1 = getActiveDuplicateCTNodePath("combattracker.list.id-00001")
            local bPass1 = (path1 == "combattracker.list.id-00004")

            -- Scenario 2: Verify target resolution on duplicate turn attack
            ActorManager.resolvedTargetNode = nil
            displayProcessAttackFromStealth = function(source, target)
                ActorManager.resolvedTargetNode = target and target.sCTNode
            end

            local rSource = { sCTNode = "combattracker.list.id-00001" }
            onRollAttack(rSource, nil, { sType = "attack" })
            local bPass2 = (ActorManager.resolvedTargetNode == "combattracker.list.id-00005")

            -- Scenario 3: Verify resolveTargetDuplicateCTNode name-based redirection (targeted)
            local rGoblin = { sCTNode = "combattracker.list.id-00002" }
            local rDurin1 = { sCTNode = "combattracker.list.id-00003" }
            local rResolved = resolveTargetDuplicateCTNode(rGoblin, rDurin1)
            local bPass3 = (rResolved and rResolved.getPath and rResolved.getPath() == "combattracker.list.id-00004")

            -- Scenario 4: Verify resolveTargetDuplicateCTNode fallback for drops (no selected targets)
            function TargetingManager.getFullTargets(rSource)
                return {}
            end
            function CombatManager.getSortedCombatantList()
                return { ActorManager.node3, ActorManager.node4 }
            end
            function getStealthNumberFromEffects(node)
                if node == ActorManager.node3 then return 7 end
                if node == ActorManager.node4 then return 18 end
                return nil
            end
            function ActorManager.resolveActor(node)
                if node == ActorManager.node3 then return { sCTNode = "combattracker.list.id-00003" } end
                if node == ActorManager.node4 then return { sCTNode = "combattracker.list.id-00004" } end
                return nil
            end

            local rGoblinNoTarget = { sCTNode = "combattracker.list.id-00002" }
            local rResolvedDrop = resolveTargetDuplicateCTNode(rGoblinNoTarget, rDurin1)
            local bPass4 = (rResolvedDrop and rResolvedDrop.sCTNode == "combattracker.list.id-00004")

            -- Restore mocked globals
            ActorManager.getCTNode = fRealGetCTNode
            CombatManager.getActiveCT = fRealGetActiveCT
            ActorManager.getCreatureNode = fRealGetCreatureNode
            ActorManager.getDisplayName = fRealGetDisplayName
            CombatManager.getSortedCombatantList = fRealGetSortedCombatantList
            getStealthNumberFromEffects = fRealGetStealthNumberFromEffects
            ActorManager.resolveActor = fRealResolveActor
            displayProcessAttackFromStealth = fRealDisplay
            if fRealGetFullTargets then
                TargetingManager.getFullTargets = fRealGetFullTargets
            else
                TargetingManager.getFullTargets = nil
            end

            return bPass1 and bPass2 and bPass3 and bPass4
        `
    );

    await runAssert("stealth-effect-visibility-options-none-effects-all", true, `
        local lastAddEffectParams = nil
        local mockEffectNode = nil

        local fRealAddEffect = EffectManager.addEffect
        EffectManager.addEffect = function(sUser, sIdentity, nodeCT, rEffect, bShowMsg)
            lastAddEffectParams = {
                sUser = sUser,
                sIdentity = sIdentity,
                nodeCT = nodeCT,
                rEffect = rEffect,
                bShowMsg = bShowMsg
            }
            -- Create mock effect node in DB
            local nodeEffects = nodeCT.getChild("effects")
            if not nodeEffects then
                nodeEffects = createMockNode({})
                nodeCT.data["effects"] = nodeEffects.data
            end
            local nodeNewEffect = createMockNode({
                label = rEffect.sName,
                isgmonly = rEffect.nGMOnly or 0
            })
            nodeEffects.data["eff1"] = nodeNewEffect.data
            mockEffectNode = nodeNewEffect
        end

        local mockCTNode = createMockNode({
            recordType = "pc",
            faction = "friend",
            initresult = 10,
            effects = {}
        })

        local fRealGetCTNode = ActorManager.getCTNode
        ActorManager.getCTNode = function(sNode) return mockCTNode end

        -- Test 1: Visibility = NONE ("none")
        OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "none"
        mockCTNode.data["effects"] = {}
        setNodeWithStealthValue("combattracker.list.id-00001", 15)

        local bTestNoneMsg = (lastAddEffectParams.bShowMsg == false)
        local bTestNoneGMOnly = (lastAddEffectParams.rEffect.nGMOnly == 1)
        local bTestNoneDBGMOnly = (mockCTNode.data.effects.eff1.isgmonly == 1)

        -- Test 2: Visibility = EFFECTS ("effects")
        OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "effects"
        mockCTNode.data["effects"] = {}
        setNodeWithStealthValue("combattracker.list.id-00001", 15)

        local bTestEffectsMsg = (lastAddEffectParams.bShowMsg == false)
        local bTestEffectsGMOnly = (lastAddEffectParams.rEffect.nGMOnly == 0)

        -- Test 3: Visibility = ALL ("all")
        OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "all"
        mockCTNode.data["effects"] = {}
        setNodeWithStealthValue("combattracker.list.id-00001", 15)

        local bTestAllMsg = (lastAddEffectParams.bShowMsg == true)
        local bTestAllGMOnly = (lastAddEffectParams.rEffect.nGMOnly == 0)

        -- Restore
        EffectManager.addEffect = fRealAddEffect
        ActorManager.getCTNode = fRealGetCTNode

        return bTestNoneMsg and bTestNoneGMOnly and bTestNoneDBGMOnly and bTestEffectsMsg and bTestEffectsGMOnly and bTestAllMsg and bTestAllGMOnly
    `);

    // --- GROUP N: Generic Actions (Hide) and Advantage Decoding Idempotency ---
    runAssert(
        "generic-actions-hide-already-decoded-no-double-decode",
        true,
        `
            local nDecodeCalls = 0
            ActionD20 = ActionD20 or {}
            ActionD20.decodeAdvantage = function(rRoll)
                nDecodeCalls = nDecodeCalls + 1
                if rRoll and rRoll.sDesc then
                    rRoll.sDesc = rRoll.sDesc:gsub("%[ADV%]", "[ADV] [DROPPED 2]")
                end
            end

            local rRollGA = {
                sType = "genactroll",
                sGenericAction = "Hide",
                sDesc = "[EFFECTS +3] [ADV] [DROPPED 2] Stealth(6) - ask DM if successful",
                aDice = { { type = "d20", result = 6 } },
                nMod = 3
            }
            local mockSource = { sCTNode = "combattracker.list.id-00001" }

            -- Simulate Generic Actions post-roll invocation
            onGenericActionPostRoll(mockSource, rRollGA)

            -- ActionD20.decodeAdvantage must NOT have been called because GA already decoded it
            local bCallsZero = (nDecodeCalls == 0)
            -- Description must NOT have duplicate [ADV] [DROPPED 2]
            local bDescUntouched = (rRollGA.sDesc == "[EFFECTS +3] [ADV] [DROPPED 2] Stealth(6) - ask DM if successful")

            return bCallsZero and bDescUntouched
        `
    );

    await runAssert(
        "ruleset-skill-already-decoded-no-double-decode",
        true,
        `
            local nDecodeCalls = 0
            ActionD20 = ActionD20 or {}
            ActionD20.decodeAdvantage = function(rRoll)
                nDecodeCalls = nDecodeCalls + 1
                if rRoll and rRoll.sDesc then
                    rRoll.sDesc = rRoll.sDesc:gsub("%[ADV%]", "[ADV] [DROPPED 2]")
                end
            end

            local rRollSkill = {
                sType = "skill",
                sDesc = "[SKILL] Stealth [ADV] [DROPPED 3]",
                aDice = { { type = "d20", result = 15 } },
                nMod = 5
            }
            local mockSource = { sCTNode = "combattracker.list.id-00001" }

            onRollSkill(mockSource, nil, rRollSkill)

            local bCallsZero = (nDecodeCalls == 0)
            local bDescUntouched = (rRollSkill.sDesc == "[SKILL] Stealth [ADV] [DROPPED 3]")

            return bCallsZero and bDescUntouched
        `
    );

    await runAssert(
        "undecoded-roll-with-adv-is-decoded-once",
        true,
        `
            local nDecodeCalls = 0
            ActionD20 = ActionD20 or {}
            ActionD20.decodeAdvantage = function(rRoll)
                nDecodeCalls = nDecodeCalls + 1
                if rRoll and rRoll.sDesc then
                    rRoll.sDesc = rRoll.sDesc:gsub("%[ADV%]", "[ADV] [DROPPED 2]")
                end
            end

            local rRollRaw = {
                sType = "skill",
                sDesc = "[SKILL] Stealth [ADV]",
                aDice = { { type = "d20", result = 15 }, { type = "d20", result = 2 } },
                nMod = 5
            }
            local mockSource = { sCTNode = "combattracker.list.id-00001" }

            onRollSkill(mockSource, nil, rRollRaw)

            -- Must be decoded exactly once
            local bCallsOne = (nDecodeCalls == 1)
            local bDescModified = (rRollRaw.sDesc == "[SKILL] Stealth [ADV] [DROPPED 2]")

            -- Second invocation on same roll must be a no-op (idempotent)
            onRollSkill(mockSource, nil, rRollRaw)

            local bCallsStillOne = (nDecodeCalls == 1)
            local bDescStillSingle = (rRollRaw.sDesc == "[SKILL] Stealth [ADV] [DROPPED 2]")

            return bCallsOne and bDescModified and bCallsStillOne and bDescStillSingle
        `
    );

    await runAssert(
        "generic-actions-hide-case-insensitivity",
        true,
        `
            local lastStealthRecorded = nil
            local fRealSetNode = setNodeWithStealthValue
            setNodeWithStealthValue = function(sNode, nTotal)
                lastStealthRecorded = nTotal
            end

            local rRollGA_lower = {
                sType = "genactroll",
                sGenericAction = "hide",
                sDesc = "[EFFECTS +2] Stealth(14)",
                aDice = { { type = "d20", result = 14 } },
                nMod = 2
            }
            local mockSource = { sCTNode = "combattracker.list.id-00001" }

            -- Enable allow out of combat so setNodeWithStealthValue is reached
            OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "all"
            local fRealIsOption = OptionsManager.isOption
            OptionsManager.isOption = function(k, v)
                if k == "STEALTHTRACKER_ALLOW_OUT_OF" and v == "all" then return true end
                return false
            end

            onGenericActionPostRoll(mockSource, rRollGA_lower)

            setNodeWithStealthValue = fRealSetNode
            OptionsManager.isOption = fRealIsOption
            return lastStealthRecorded == 16
        `
    );

    // --- GROUP O: Turn Checks & End-to-End Stealth Roll Resolution ---
    await runAssert(
        "turn-check-in-combat-in-turn",
        true,
        `
            local node1 = createMockNode({ recordType = "pc" })
            function node1.getPath() return "combattracker.list.id-00001" end

            local fRealActive = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return node1 end

            local bAllow = checkAndDisplayAllowOutOfCombatAndTurnChecks(node1)
            CombatManager.getActiveCT = fRealActive
            return bAllow
        `
    );

    await runAssert(
        "turn-check-out-of-turn-blocked",
        false,
        `
            local node1 = createMockNode({ recordType = "pc" })
            function node1.getPath() return "combattracker.list.id-00001" end
            local node2 = createMockNode({ recordType = "npc" })
            function node2.getPath() return "combattracker.list.id-00002" end

            local fRealActive = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return node2 end
            OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "off"

            local bAllow = checkAndDisplayAllowOutOfCombatAndTurnChecks(node1)
            CombatManager.getActiveCT = fRealActive
            return bAllow
        `
    );

    await runAssert(
        "turn-check-out-of-turn-allowed-when-option-enabled",
        true,
        `
            local node1 = createMockNode({ recordType = "pc" })
            function node1.getPath() return "combattracker.list.id-00001" end
            local node2 = createMockNode({ recordType = "npc" })
            function node2.getPath() return "combattracker.list.id-00002" end

            local fRealActive = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return node2 end
            OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "turn"

            local bAllow = checkAndDisplayAllowOutOfCombatAndTurnChecks(node1)
            CombatManager.getActiveCT = fRealActive
            OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "off"
            return bAllow
        `
    );

    await runAssert(
        "pc-stealth-roll-end-to-end-resolves-effect",
        true,
        `
            local lastEffectAdded = nil
            local fRealAddEffect = EffectManager.addEffect
            EffectManager.addEffect = function(sUser, sIdentity, nodeCT, rEffect, bShowMsg)
                lastEffectAdded = rEffect
            end

            local mockPC = createMockNode({
                recordType = "pc",
                faction = "friend",
                initresult = 12,
                effects = {}
            })
            function mockPC.getPath() return "combattracker.list.id-00001" end

            local fRealGetCTNode = ActorManager.getCTNode
            ActorManager.getCTNode = function(s) return mockPC end

            local fRealActive = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return mockPC end

            OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "off"
            OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "all"

            local fSkillHandler = ActionsManager.getResultHandler("skill")
            local rRoll = {
                sType = "skill",
                sDesc = "[SKILL] Stealth [MOD:5]",
                aDice = { { type = "d20", result = 14 } },
                nMod = 5
            }
            local rSource = { sCTNode = "combattracker.list.id-00001" }

            fSkillHandler(rSource, nil, rRoll)

            EffectManager.addEffect = fRealAddEffect
            ActorManager.getCTNode = fRealGetCTNode
            CombatManager.getActiveCT = fRealActive

            return lastEffectAdded ~= nil
               and lastEffectAdded.sName == "Stealth: 19"
               and lastEffectAdded.nGMOnly == 0
        `
    );

    await runAssert(
        "npc-stealth-roll-end-to-end-resolves-gm-only-effect",
        true,
        `
            local lastEffectAdded = nil
            local fRealAddEffect = EffectManager.addEffect
            EffectManager.addEffect = function(sUser, sIdentity, nodeCT, rEffect, bShowMsg)
                lastEffectAdded = rEffect
            end

            local mockNPC = createMockNode({
                recordType = "npc",
                faction = "foe",
                initresult = 8,
                effects = {}
            })
            function mockNPC.getPath() return "combattracker.list.id-00002" end

            local fRealGetCTNode = ActorManager.getCTNode
            ActorManager.getCTNode = function(s) return mockNPC end

            local fRealActive = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return mockNPC end

            OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "off"
            OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "all"

            local fSkillHandler = ActionsManager.getResultHandler("skill")
            local rRoll = {
                sType = "skill",
                sDesc = "[SKILL] Stealth [MOD:3]",
                aDice = { { type = "d20", result = 11 } },
                nMod = 3
            }
            local rSource = { sCTNode = "combattracker.list.id-00002" }

            fSkillHandler(rSource, nil, rRoll)

            EffectManager.addEffect = fRealAddEffect
            ActorManager.getCTNode = fRealGetCTNode
            CombatManager.getActiveCT = fRealActive

            return lastEffectAdded ~= nil
               and lastEffectAdded.sName == "Stealth: 14"
               and lastEffectAdded.nGMOnly == 1
        `
    );

    await runAssert(
        "ct-hidden-actor-stealth-roll-flagged-secret",
        true,
        `
            local mockNPC = createMockNode({
                recordType = "npc",
                faction = "foe",
                initresult = 8,
                effects = {}
            })
            function mockNPC.getPath() return "combattracker.list.id-00002" end

            local fRealGetCTNode = ActorManager.getCTNode
            ActorManager.getCTNode = function(s) return mockNPC end

            local fRealIsCTHidden = CombatManager.isCTHidden
            CombatManager.isCTHidden = function(node) return true end

            local fSkillHandler = ActionsManager.getResultHandler("skill")
            local rRoll = {
                sType = "skill",
                sDesc = "[SKILL] Stealth",
                aDice = { { type = "d20", result = 10 } },
                nMod = 2
            }
            local rSource = { sCTNode = "combattracker.list.id-00002" }

            fSkillHandler(rSource, nil, rRoll)

            ActorManager.getCTNode = fRealGetCTNode
            CombatManager.isCTHidden = fRealIsCTHidden

            return rRoll.bSecret == true
        `
    );

    await runAssert(
        "ensureStealthSkillExistsOnNpc-adds-stealth-when-missing",
        "Stealth +2",
        `
            local mockNPC = createMockNode({
                recordType = "npc",
                faction = "foe",
                abilities = { dexterity = { bonus = 2 } },
                skills = ""
            })
            ensureStealthSkillExistsOnNpc(mockNPC)
            return DB.getValue(mockNPC, "skills", "")
        `
    );

    await runAssert(
        "ensureStealthSkillExistsOnNpc-prepends-to-existing-skills",
        "Stealth +2, Perception +4",
        `
            local mockNPC = createMockNode({
                recordType = "npc",
                faction = "foe",
                abilities = { dexterity = { bonus = 2 } },
                skills = "Perception +4"
            })
            ensureStealthSkillExistsOnNpc(mockNPC)
            return DB.getValue(mockNPC, "skills", "")
        `
    );

    await runAssert(
        "ensureStealthSkillExistsOnNpc-preserves-existing-stealth",
        "Stealth +5, Perception +4",
        `
            local mockNPC = createMockNode({
                recordType = "npc",
                faction = "foe",
                abilities = { dexterity = { bonus = 2 } },
                skills = "Stealth +5, Perception +4"
            })
            ensureStealthSkillExistsOnNpc(mockNPC)
            return DB.getValue(mockNPC, "skills", "")
        `
    );

    await runAssert(
        "checkFGC-detection",
        true,
        `
            UtilityManager = { isClientFGU = function() return false end }
            local bFGC = checkFGC()
            UtilityManager = { isClientFGU = function() return true end }
            local bNotFGC = not checkFGC()

            -- Test fallback with Interface.getVersion semantic strings when UtilityManager/Session are nil
            local tSavedUtility = UtilityManager
            local tSavedSession = Session
            UtilityManager = nil
            Session = nil

            Interface.getVersion = function() return "3.3.14" end
            local bFGCVersion = checkFGC()

            Interface.getVersion = function() return "4.5.1" end
            local bFGUVersion = not checkFGC()

            UtilityManager = tSavedUtility
            Session = tSavedSession
            return bFGC and bNotFGC and bFGCVersion and bFGUVersion
        `
    );

    await runAssert(
        "fgc-exhaustion-disadvantage",
        true,
        `
            IS_FGC = true
            local mockPC = createMockNode({ recordType = "pc", abilities = { wisdom = { score = 10, bonus = 0 } } })
            local fRealGetBonus = EffectManager5E.getEffectsBonus
            -- In FGC 5E manager_effect_5E.lua: if bModOnly then return nTotalMod, nEffectCount end
            EffectManager5E.getEffectsBonus = function(node, aTypes, bFirst)
                if aTypes[1] == "EXHAUSTION" then
                    if bFirst then
                        return 0, 1
                    end
                    return {}, 0, 1
                end
                if bFirst then
                    return 0, 0
                end
                return {}, 0, 0
            end
            local bAdv, bDis, nMod = getAdvDisadvForPerception(mockPC)
            EffectManager5E.getEffectsBonus = fRealGetBonus
            IS_FGC = false
            return bDis == true
        `
    );

    await runAssert(
        "fgc-exhaustion-no-exhaustion-no-nil-error",
        true,
        `
            IS_FGC = true
            local mockPC = createMockNode({ recordType = "pc", abilities = { wisdom = { score = 10, bonus = 0 } } })
            local fRealGetBonus = EffectManager5E.getEffectsBonus
            -- In FGC 5E, when no exhaustion exists, getEffectsBonus with bModOnly=true returns 0, 0
            EffectManager5E.getEffectsBonus = function(node, aTypes, bFirst)
                if bFirst then
                    return 0, 0
                end
                return {}, 0, 0
            end
            local bOk, bAdv, bDis, nMod = pcall(function()
                return getAdvDisadvForPerception(mockPC)
            end)
            EffectManager5E.getEffectsBonus = fRealGetBonus
            IS_FGC = false
            return bOk == true and bDis == false
        `
    );

    await runAssert(
        "fgc-onDrop-deduplication",
        true,
        `
            IS_FGC = true
            local nDropEventCalls = 0
            local fRealOnDropEvent = onDropEvent
            onDropEvent = function() nDropEventCalls = nDropEventCalls + 1 end

            local mockDrag = { type = "number", getNumberData = function() return 15 end, getStringData = function() return "[SKILL] Stealth" end }
            onDrop("ct", "combattracker.list.id-00001", mockDrag)
            -- Immediate identical second drop should be ignored
            onDrop("ct", "combattracker.list.id-00001", mockDrag)

            onDropEvent = fRealOnDropEvent
            IS_FGC = false
            return nDropEventCalls == 1
        `
    );

    await runAssert(
        "fgc-getResultHandlerSafe-fallback",
        true,
        `
            local fRealGetResultHandler = ActionsManager.getResultHandler
            ActionsManager.getResultHandler = nil
            local tSavedHandlers = ActionsManager.aHandlers
            local tRegistered = {}
            ActionsManager.aHandlers = nil
            local fRealRegister = ActionsManager.registerResultHandler
            ActionsManager.registerResultHandler = function(sType, fn)
                tRegistered[sType] = fn
            end

            local bSkillCalled = false
            local bAttackCalled = false
            ActionSkill = { onRoll = function() bSkillCalled = true end }
            ActionAttack = { onAttack = function() bAttackCalled = true end }

            bStealthTrackerInitialized = false
            onInit()

            local fSkill = tRegistered["skill"]
            local fAttack = tRegistered["attack"]
            fSkill(createMockNode({ recordType = "pc" }), nil, { sType = "skill", sDesc = "[skill] stealth", aDice = { { type = "d20", result = 10 } } })
            fAttack(createMockNode({ recordType = "pc" }), nil, { sType = "attack" })

            ActionsManager.getResultHandler = fRealGetResultHandler
            ActionsManager.aHandlers = tSavedHandlers
            ActionsManager.registerResultHandler = fRealRegister
            return bSkillCalled and bAttackCalled
        `
    );

    await runAssert(
        "fgc-getActorSafe-uses-resolveActor",
        true,
        `
            IS_FGC = true
            local mockNode = createMockNode({ recordType = "pc" })
            local fRealGetActor = ActorManager.getActor
            local fRealResolveActor = ActorManager.resolveActor
            
            -- Simulate FGC where getActor takes (sOldType, v) and returns nil when called with 1 arg
            ActorManager.getActor = function(sOldType, v) return nil end
            local bResolveCalled = false
            ActorManager.resolveActor = function(v)
                bResolveCalled = true
                return { sCTNode = "mock.path", sType = "pc", sName = "MockPC" }
            end
            
            local rActor = getActorSafe(mockNode)
            
            ActorManager.getActor = fRealGetActor
            ActorManager.resolveActor = fRealResolveActor
            IS_FGC = false
            return bResolveCalled and rActor ~= nil and rActor.sName == "MockPC"
        `
    );

    await runAssert(
        "fgc-turn-activation-outputs-stealth-analysis",
        true,
        `
            IS_FGC = true
            USER_ISHOST = true
            local tSavedOptions = OptionsManager_mock_options
            OptionsManager_mock_options = {
                ["STEALTHTRACKER_VISIBLE"] = "hidden",
                ["STEALTHTRACKER_AWARE"] = "both",
                ["STEALTHTRACKER_VERBOSE"] = "standard"
            }

            local mockPC = createMockNode({
                recordType = "pc",
                faction = "friend",
                perception = 12
            })
            function mockPC.getPath() return "combattracker.list.id-00001" end

            local mockGoblin = createMockNode({
                recordType = "npc",
                faction = "foe",
                type = "humanoid",
                name = "Goblin",
                senses = "passive Perception 9",
                effects = {
                    id1 = { label = "Stealth: 18", isgmonly = 1 }
                }
            })
            function mockGoblin.getPath() return "combattracker.list.id-00002" end

            local fRealGetSorted = CombatManager.getSortedCombatantList
            CombatManager.getSortedCombatantList = function()
                return { mockPC, mockGoblin }
            end

            local sLastChatMsg = nil
            local fRealAddChatMessage = Comm.addChatMessage
            Comm.addChatMessage = function(msg)
                sLastChatMsg = msg.text
            end

            -- Simulate clicking next turn in CT (turn activates on PC)
            requestActivation(mockPC, false)

            CombatManager.getSortedCombatantList = fRealGetSorted
            Comm.addChatMessage = fRealAddChatMessage
            OptionsManager_mock_options = tSavedOptions
            IS_FGC = false

            return sLastChatMsg ~= nil
               and sLastChatMsg:find("does not perceive") ~= nil
               and sLastChatMsg:find("Stealth: 18") ~= nil
        `
    );

    await runAssert(
        "fgc-turn-activation-hiding-actor-unaware-analysis",
        true,
        `
            IS_FGC = true
            USER_ISHOST = true
            local tSavedOptions = OptionsManager_mock_options
            OptionsManager_mock_options = {
                ["STEALTHTRACKER_VISIBLE"] = "hidden",
                ["STEALTHTRACKER_AWARE"] = "both",
                ["STEALTHTRACKER_VERBOSE"] = "standard"
            }

            local mockPC = createMockNode({
                recordType = "pc",
                faction = "friend",
                name = "Valeros",
                perception = 12
            })
            function mockPC.getPath() return "combattracker.list.id-00001" end

            local mockGoblin = createMockNode({
                recordType = "npc",
                faction = "foe",
                type = "humanoid",
                name = "Goblin",
                senses = "passive Perception 9",
                effects = {
                    id1 = { label = "Stealth: 18", isgmonly = 1 }
                }
            })
            function mockGoblin.getPath() return "combattracker.list.id-00002" end

            local fRealGetSorted = CombatManager.getSortedCombatantList
            CombatManager.getSortedCombatantList = function()
                return { mockPC, mockGoblin }
            end

            local sLastChatMsg = nil
            local fRealAddChatMessage = Comm.addChatMessage
            Comm.addChatMessage = function(msg)
                sLastChatMsg = msg.text
            end

            -- Simulate clicking next turn in CT onto the hiding Goblin
            requestActivation(mockGoblin, false)

            CombatManager.getSortedCombatantList = fRealGetSorted
            Comm.addChatMessage = fRealAddChatMessage
            OptionsManager_mock_options = tSavedOptions
            IS_FGC = false

            return sLastChatMsg ~= nil
               and sLastChatMsg:find("is hidden from") ~= nil
               and sLastChatMsg:find("Stealth: 18") ~= nil
        `
    );

    // --- GROUP XIV: Attack From Stealth Message Generation ---
    await runAssert(
        "attack-from-stealth-adv-message-on-non-hiding-target",
        true,
        `
            local tSavedOptions = {}
            for k, v in pairs(OptionsManager_mock_options) do tSavedOptions[k] = v end
            OptionsManager_mock_options["STEALTHTRACKER_VERBOSE"] = "standard"

            local mockRogue = createMockNode({
                recordType = "pc",
                faction = "friend",
                name = "Rogue",
                perception = 14,
                effects = {
                    id1 = { label = "Stealth: 18", isgmonly = 0 }
                }
            })
            function mockRogue.getPath() return "combattracker.list.id-00010" end

            local mockGoblin = createMockNode({
                recordType = "npc",
                faction = "foe",
                type = "humanoid",
                name = "Goblin",
                senses = "passive Perception 10"
            })
            function mockGoblin.getPath() return "combattracker.list.id-00011" end

            local fRealGetActiveCT = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return mockRogue end

            local sLastChatMsg = nil
            local fRealAddChatMessage = Comm.addChatMessage
            Comm.addChatMessage = function(msg)
                sLastChatMsg = msg.text
            end

            local rSource = ActorManager.resolveActor(mockRogue)
            local rTarget = ActorManager.resolveActor(mockGoblin)

            displayProcessAttackFromStealth(rSource, rTarget)

            CombatManager.getActiveCT = fRealGetActiveCT
            Comm.addChatMessage = fRealAddChatMessage
            OptionsManager_mock_options = tSavedOptions

            return sLastChatMsg ~= nil
               and sLastChatMsg:find("Attacker is hidden. Attack at advantage%?") ~= nil
               and sLastChatMsg:find("S: 18") ~= nil
               and sLastChatMsg:find("PP: 10") ~= nil
        `
    );

    await runAssert(
        "attack-from-stealth-spotted-verbosity-max-vs-standard",
        true,
        `
            local tSavedOptions = {}
            for k, v in pairs(OptionsManager_mock_options) do tSavedOptions[k] = v end

            local mockRogue = createMockNode({
                recordType = "pc",
                faction = "friend",
                name = "Rogue",
                perception = 10,
                effects = {
                    id1 = { label = "Stealth: 8", isgmonly = 0 }
                }
            })
            function mockRogue.getPath() return "combattracker.list.id-00020" end

            local mockGuard = createMockNode({
                recordType = "npc",
                faction = "foe",
                name = "Guard",
                senses = "passive Perception 14"
            })
            function mockGuard.getPath() return "combattracker.list.id-00021" end

            local fRealGetActiveCT = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return mockRogue end

            local sLastChatMsg = nil
            local fRealAddChatMessage = Comm.addChatMessage
            Comm.addChatMessage = function(msg)
                sLastChatMsg = msg.text
            end

            local rSource = ActorManager.resolveActor(mockRogue)
            local rTarget = ActorManager.resolveActor(mockGuard)

            -- Standard verbosity: attacker spotted, so no chat message expected
            OptionsManager_mock_options["STEALTHTRACKER_VERBOSE"] = "standard"
            displayProcessAttackFromStealth(rSource, rTarget)
            local bStandardNil = (sLastChatMsg == nil)

            -- Re-add effect for max verbosity test
            DB.setValue(mockRogue, "effects.id2.label", "string", "Stealth: 8")
            OptionsManager_mock_options["STEALTHTRACKER_VERBOSE"] = "max"
            sLastChatMsg = nil
            displayProcessAttackFromStealth(rSource, rTarget)
            local bMaxShowsNotHidden = (sLastChatMsg ~= nil and sLastChatMsg:find("Attacker not hidden") ~= nil)

            CombatManager.getActiveCT = fRealGetActiveCT
            Comm.addChatMessage = fRealAddChatMessage
            OptionsManager_mock_options = tSavedOptions

            return bStandardNil and bMaxShowsNotHidden
        `
    );

    await runAssert(
        "fgc-end-to-end-attack-from-stealth-in-ct",
        true,
        `
            local tSavedOptions = {}
            for k, v in pairs(OptionsManager_mock_options) do tSavedOptions[k] = v end
            OptionsManager_mock_options["STEALTHTRACKER_VERBOSE"] = "standard"
            IS_FGC = true

            local mockPC = createMockNode({
                recordType = "pc",
                faction = "friend",
                name = "Shadow",
                perception = 12,
                effects = {
                    id1 = { label = "Stealth: 17", isgmonly = 0 }
                }
            })
            function mockPC.getPath() return "combattracker.list.id-00030" end

            local mockTarget = createMockNode({
                recordType = "npc",
                faction = "foe",
                name = "Orc",
                senses = "passive Perception 11"
            })
            function mockTarget.getPath() return "combattracker.list.id-00031" end

            local fRealGetActiveCT = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return mockPC end

            local sLastChatMsg = nil
            local fRealAddChatMessage = Comm.addChatMessage
            Comm.addChatMessage = function(msg)
                sLastChatMsg = msg.text
            end

            -- Simulate attack roll handler invocation in FGC
            local rSource = ActorManager.resolveActor(mockPC)
            local rTarget = ActorManager.resolveActor(mockTarget)
            onRollAttack(rSource, rTarget, { sType = "attack" })

            CombatManager.getActiveCT = fRealGetActiveCT
            Comm.addChatMessage = fRealAddChatMessage
            OptionsManager_mock_options = tSavedOptions
            IS_FGC = false

            return sLastChatMsg ~= nil
               and sLastChatMsg:find("Attacker is hidden. Attack at advantage%?") ~= nil
               and sLastChatMsg:find("S: 17") ~= nil
               and sLastChatMsg:find("PP: 11") ~= nil
        `
    );

    await runAssert(
        "attack-from-stealth-both-attacker-and-target-hidden",
        true,
        `
            local tSavedOptions = {}
            for k, v in pairs(OptionsManager_mock_options) do tSavedOptions[k] = v end
            OptionsManager_mock_options["STEALTHTRACKER_VERBOSE"] = "standard"

            local mockPC = createMockNode({
                recordType = "pc",
                faction = "friend",
                name = "Shadow",
                perception = 12,
                effects = {
                    id1 = { label = "Stealth: 17", isgmonly = 0 }
                }
            })
            function mockPC.getPath() return "combattracker.list.id-00040" end

            local mockNinja = createMockNode({
                recordType = "npc",
                faction = "foe",
                name = "Ninja",
                senses = "passive Perception 10",
                effects = {
                    id1 = { label = "Stealth: 19", isgmonly = 1 }
                }
            })
            function mockNinja.getPath() return "combattracker.list.id-00041" end

            local fRealGetActiveCT = CombatManager.getActiveCT
            CombatManager.getActiveCT = function() return mockPC end

            local sLastChatMsg = nil
            local fRealAddChatMessage = Comm.addChatMessage
            Comm.addChatMessage = function(msg)
                sLastChatMsg = msg.text
            end

            local rSource = ActorManager.resolveActor(mockPC)
            local rTarget = ActorManager.resolveActor(mockNinja)
            displayProcessAttackFromStealth(rSource, rTarget)

            CombatManager.getActiveCT = fRealGetActiveCT
            Comm.addChatMessage = fRealAddChatMessage
            OptionsManager_mock_options = tSavedOptions

            return sLastChatMsg ~= nil
               and sLastChatMsg:find("Target hidden. Attack possible%?") ~= nil
               and sLastChatMsg:find("Attacker is hidden. Attack at advantage%?") ~= nil
        `
    );

    // --- GROUP XV: v5.8 Dice Tower Auto-GM-Only & Client-Side Option Lookup ---
    await runAssert(
        "v5.8 dice-tower-auto-gm-only-and-client-option-lookup",
        "",
        `
            local failures = {}
            local function fail(msg) table.insert(failures, msg) end

            -- 1. Client-side DB fallback in isPlayerStealthInfoDisabled when OptionsManager returns ""
            do
                local fRealGetOption = OptionsManager.getOption
                local fRealDBGetValue = DB.getValue

                OptionsManager.getOption = function(key) return "" end
                DB.getValue = function(nodeOrPath, pathOrDefault, defaultVal)
                    if nodeOrPath == "options.STEALTHTRACKER_VISIBILITY" then
                        return "none"
                    end
                    return fRealDBGetValue(nodeOrPath, pathOrDefault, defaultVal)
                end

                if not isPlayerStealthInfoDisabled() then
                    fail("isPlayerStealthInfoDisabled failed to detect 'none' via DB.getValue on client")
                end

                local rRoll = { sType = "skill", sDesc = "[SKILL] Stealth" }
                local rSource = createMockNode({ recordType = "pc" })
                onInitiateSkill(rSource, nil, rRoll)
                if rRoll.bSecret ~= true then
                    fail("onInitiateSkill failed to set rRoll.bSecret = true on client when DB option is 'none'")
                end

                DB.getValue = function(nodeOrPath, pathOrDefault, defaultVal)
                    if nodeOrPath == "options.STEALTHTRACKER_VISIBILITY" then
                        return "effects"
                    end
                    return fRealDBGetValue(nodeOrPath, pathOrDefault, defaultVal)
                end
                if isPlayerStealthInfoDisabled() then
                    fail("isPlayerStealthInfoDisabled returned true when DB option is 'effects'")
                end

                OptionsManager.getOption = fRealGetOption
                DB.getValue = fRealDBGetValue
            end

            -- 2. Dice Tower / secret PC stealth roll creates GM-only effect even when visibility is 'effects' or 'all'
            do
                local lastAddEffectParams = nil
                local fRealAddEffect = EffectManager.addEffect
                EffectManager.addEffect = function(sUser, sIdentity, nodeCT, rEffect, bShowMsg)
                    lastAddEffectParams = { rEffect = rEffect, bShowMsg = bShowMsg }
                    local nodeEffects = nodeCT.getChild("effects")
                    if not nodeEffects then
                        nodeEffects = createMockNode({})
                        nodeCT.data["effects"] = nodeEffects.data
                    end
                    local nodeNewEffect = createMockNode({
                        label = rEffect.sName,
                        isgmonly = rEffect.nGMOnly or 0
                    })
                    nodeEffects.data["eff1"] = nodeNewEffect.data
                end

                local mockPC = createMockNode({
                    recordType = "pc",
                    faction = "friend",
                    initresult = 14,
                    effects = {}
                })
                function mockPC.getPath() return "combattracker.list.id-00001" end

                local fRealGetCTNode = ActorManager.getCTNode
                ActorManager.getCTNode = function(s) return mockPC end
                local fRealActive = CombatManager.getActiveCT
                CombatManager.getActiveCT = function() return mockPC end

                USER_ISHOST = true
                OptionsManager_mock_options["STEALTHTRACKER_ALLOW_OUT_OF"] = "off"
                OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "effects"

                -- Roll with bTower = true
                local rTowerRoll = {
                    sType = "skill",
                    sDesc = "[SKILL] Stealth",
                    aDice = { { type = "d20", result = 16 } },
                    nMod = 4,
                    bTower = true
                }
                onRollSkill({ sCTNode = "combattracker.list.id-00001" }, nil, rTowerRoll)

                if not lastAddEffectParams or lastAddEffectParams.rEffect.nGMOnly ~= 1 then
                    fail("Tower PC stealth roll did not set nGMOnly = 1 when visibility = 'effects'")
                end
                if mockPC.data.effects.eff1.isgmonly ~= 1 then
                    fail("Tower PC stealth roll did not set DB isgmonly = 1")
                end
                if lastAddEffectParams.bShowMsg ~= false then
                    fail("Tower PC stealth roll did not suppress chat message")
                end

                -- Roll with bSecret = true and visibility = 'all'
                OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "all"
                mockPC.data["effects"] = {}
                lastAddEffectParams = nil
                local rSecretRoll = {
                    sType = "skill",
                    sDesc = "[SKILL] Stealth",
                    aDice = { { type = "d20", result = 12 } },
                    nMod = 4,
                    bSecret = true
                }
                onRollSkill({ sCTNode = "combattracker.list.id-00001" }, nil, rSecretRoll)

                if not lastAddEffectParams or lastAddEffectParams.rEffect.nGMOnly ~= 1 or lastAddEffectParams.bShowMsg ~= false then
                    fail("Secret PC stealth roll did not enforce GM-only and suppress chat when visibility = 'all'")
                end

                -- OOB round-trip from client with bSecret = true
                local sentOOB = nil
                local fRealDeliverOOB = Comm.deliverOOBMessage
                local fRealGetUsername = User.getUsername
                User.getUsername = function() return "Player1" end
                Comm.deliverOOBMessage = function(msg) sentOOB = msg end

                notifyUpdateStealth("combattracker.list.id-00001", 16, true)
                if not sentOOB or sentOOB.bSecret ~= "1" then
                    fail("notifyUpdateStealth did not serialize bSecret = '1' in OOB message")
                end

                mockPC.data["effects"] = {}
                lastAddEffectParams = nil
                handleUpdateStealth(sentOOB)
                if not lastAddEffectParams or lastAddEffectParams.rEffect.nGMOnly ~= 1 then
                    fail("handleUpdateStealth did not preserve bSecret from OOB message")
                end

                Comm.deliverOOBMessage = fRealDeliverOOB
                User.getUsername = fRealGetUsername
                EffectManager.addEffect = fRealAddEffect
                ActorManager.getCTNode = fRealGetCTNode
                CombatManager.getActiveCT = fRealActive
            end

            -- 3. STEALTH_EFFECT_MODIFIERS ('Cloak of Elvenkind' -5 PP modifier & formatted PP string)
            do
                local fRealHasEffect = EffectManager.hasEffect
                local mockCloaked = createMockNode({
                    recordType = "pc",
                    faction = "friend",
                    name = "ElvenRogue",
                    perception = 12,
                    hasCloak = true
                })
                local mockObserver = createMockNode({
                    recordType = "npc",
                    faction = "foe",
                    name = "Bandit",
                    senses = "passive Perception 14"
                })
                EffectManager.hasEffect = function(rActor, sEffect)
                    if rActor and rActor.data and rActor.data.hasCloak and sEffect:lower() == "cloak of elvenkind" then
                        return true
                    end
                    return false
                end

                local nMod = getStealthEffectModifier(mockCloaked)
                if nMod ~= -5 then
                    fail("Expected getStealthEffectModifier to return -5 for Cloak of Elvenkind, got " .. tostring(nMod))
                end
                local nPPEff, nPPMod = getPassivePerceptionWithModifier(mockObserver, mockCloaked)
                if nPPEff ~= 9 or nPPMod ~= -5 then
                    fail("Expected getPassivePerceptionWithModifier to return 9, -5; got " .. tostring(nPPEff) .. ", " .. tostring(nPPMod))
                end
                if getFormattedPPString(nPPEff, nPPMod) ~= "9 [14 - 5]" then
                    fail("Expected getFormattedPPString(9, -5) to be '9 [14 - 5]', got " .. tostring(getFormattedPPString(nPPEff, nPPMod)))
                end
                if getFormattedPPString(16, 2) ~= "16 [14 + 2]" then
                    fail("Expected getFormattedPPString(16, 2) to be '16 [14 + 2]', got " .. tostring(getFormattedPPString(16, 2)))
                end
                if getFormattedPPString(14, 0) ~= "14" then
                    fail("Expected getFormattedPPString(14, 0) to be '14'")
                end
                -- Bandit base PP 14, effective PP 9 vs Stealth 12 -> should NOT perceive ElvenRogue
                if doesTargetPerceiveAttackerFromStealth(12, mockObserver, mockCloaked) then
                    fail("Expected observer with base PP 14 (effective 9) not to perceive Cloak of Elvenkind wearer with Stealth 12")
                end

                EffectManager.hasEffect = fRealHasEffect
            end

            -- 4. getActorDisplayNameSafe respects unidentified NPCs; ensureStealthSkillExistsOnNpc is case-insensitive; onPerformAction marks roll secret
            do
                local mockUnidNpc = createMockNode({
                    recordType = "npc",
                    isidentified = 0,
                    name = "Ancient Vampire",
                    nonid_name = "Mysterious Cloaked Figure",
                    skills = "Perception +4, stealth   +6"
                })
                if getActorDisplayNameSafe(mockUnidNpc) ~= "Mysterious Cloaked Figure" then
                    fail("getActorDisplayNameSafe leaked true name of unidentified NPC: " .. tostring(getActorDisplayNameSafe(mockUnidNpc)))
                end
                ensureStealthSkillExistsOnNpc(mockUnidNpc)
                if mockUnidNpc.data.skills ~= "Perception +4, stealth   +6" then
                    fail("ensureStealthSkillExistsOnNpc duplicated lowercase/multi-space stealth skill: " .. tostring(mockUnidNpc.data.skills))
                end

                local fRealGetOption = OptionsManager.getOption
                OptionsManager.getOption = function(k)
                    if k == "STEALTHTRACKER_VISIBILITY" then return "none" end
                    return ""
                end
                local rActionRoll = { sType = "skill", sDesc = "[SKILL] Stealth" }
                onPerformAction(nil, mockUnidNpc, rActionRoll)
                if rActionRoll.bSecret ~= true then
                    fail("onPerformAction did not mark Stealth roll secret before roll execution")
                end
                OptionsManager.getOption = fRealGetOption
            end

            -- 5. onDropEvent with FGU chat 'number' drag (getStringData() == '', getDescription() == '[TOWER] [SKILL] Stealth')
            do
                local lastDropEffect = nil
                local fRealAddEffect = EffectManager.addEffect
                EffectManager.addEffect = function(sUser, sIdentity, nodeCT, rEffect, bShowMsg)
                    lastDropEffect = { rEffect = rEffect, bShowMsg = bShowMsg }
                end

                local mockDropPC = createMockNode({
                    recordType = "pc",
                    faction = "friend",
                    initresult = 12,
                    effects = {}
                })
                function mockDropPC.getPath() return "combattracker.list.id-00050" end
                local fRealGetCTNode = ActorManager.getCTNode
                ActorManager.getCTNode = function(s) return mockDropPC end

                USER_ISHOST = true
                OptionsManager_mock_options["STEALTHTRACKER_VISIBILITY"] = "effects"

                local mockDragInfo = {
                    getType = function() return "number" end,
                    getStringData = function() return "" end,
                    getDescription = function() return "[TOWER] [SKILL] Stealth" end,
                    getNumberData = function() return 21 end,
                    getSecret = function() return false end
                }
                onDropEvent(nil, { sCTNode = "combattracker.list.id-00050" }, mockDragInfo)
                if not lastDropEffect or lastDropEffect.rEffect.sName ~= "Stealth: 21" or lastDropEffect.rEffect.nGMOnly ~= 1 then
                    fail("onDropEvent failed to apply GM-only Stealth: 21 from FGU chat number drag with [TOWER] description")
                end

                ActorManager.getCTNode = fRealGetCTNode
                EffectManager.addEffect = fRealAddEffect
            end

            return table.concat(failures, "; ")
        `
    );

    // 4. Print Summary
    console.log(`\nTest Summary: ${testsPassed} passed, ${testsFailed} failed.`);
    
    if (testsFailed > 0) {
        process.exit(1);
    }
}

runTests().catch(err => {
    console.error("Test execution failed: ", err);
    process.exit(1);
});
