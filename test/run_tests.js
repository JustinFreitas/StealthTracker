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
        EffectManager = {}
        EffectManager5E = {}
        OOBManager = {}
        StringManager = {}
        Debug = { console = function() end }

        -- Mock StringManager
        function StringManager.isBlank(s)
            return s == nil or s == "" or s:gsub("%s+", "") == ""
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

        -- Mock OptionsManager
        OptionsManager_mock_options = {}
        function OptionsManager.getOption(key) return OptionsManager_mock_options[key] or "off" end
        function OptionsManager.isOption(key, val) return false end

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

    async function runAssert(fnName, expected, luaCodeToRun) {
        try {
            const result = await lua.doString(luaCodeToRun);
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
    await lua.doString(`
        function OptionsManager.isOption(key, val)
            if key == "STEALTHTRACKER_ALLOW_OUT_OF" and val == "all" then return true end
            return false
        end
    `);
    await runAssert("checkAllowOutOfCombat() enabled", true, "return checkAllowOutOfCombat()");
    
    // Reset isOption stub
    await lua.doString(`function OptionsManager.isOption() return false end`);

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

        -- Mock ruleset original result handlers
        function mockRulesetOnSkillRoll() end
        function mockRulesetOnAttackRoll() end
        ActionsManager.registerResultHandler("skill", mockRulesetOnSkillRoll)
        ActionsManager.registerResultHandler("attack", mockRulesetOnAttackRoll)

        -- Mock CoreRPG GameManager layered hook registry
        GameManager = {}
        GameManager.aMultiKey = {}
        function GameManager.setMultiKeyFunction(sKey, sSubKey, fn)
            GameManager.aMultiKey[sKey] = GameManager.aMultiKey[sKey] or {}
            GameManager.aMultiKey[sKey][sSubKey or ""] = fn
        end
        function GameManager.getMultiKeyFunction(sKey, sSubKey)
            return GameManager.aMultiKey[sKey] and GameManager.aMultiKey[sKey][sSubKey or ""]
        end

        -- Mock pre-existing GameManager post-resolve hook to verify chaining
        prevPostResolveCalls = 0
        GameManager.setMultiKeyFunction("onActionPostResolve", "attack", function()
            prevPostResolveCalls = prevPostResolveCalls + 1
        end)

        -- Execute onInit to install observers/wrappers
        onInit()
    `);

    await runAssert(
        "observers-installed-via-GameManager",
        true,
        `
            return type(GameManager.getMultiKeyFunction("onActionPostResolve", "skill")) == "function"
               and type(GameManager.getMultiKeyFunction("onActionPostResolve", "attack")) == "function"
        `
    );

    await runAssert(
        "ruleset-handlers-untouched",
        true,
        `
            return ActionsManager.aHandlers["skill"] == mockRulesetOnSkillRoll
               and ActionsManager.aHandlers["attack"] == mockRulesetOnAttackRoll
        `
    );

    await runAssert(
        "double-init-is-noop (idempotent init guard)",
        true,
        `
            local fBefore = GameManager.getMultiKeyFunction("onActionPostResolve", "attack")
            onInit()
            return fBefore == GameManager.getMultiKeyFunction("onActionPostResolve", "attack")
        `
    );

    await runAssert(
        "onRollAttack observer routing",
        1,
        `
            local nAttackObserved = 0
            local fRealDisplay = displayProcessAttackFromStealth
            displayProcessAttackFromStealth = function() nAttackObserved = nAttackObserved + 1 end

            local fAttackSlot = GameManager.getMultiKeyFunction("onActionPostResolve", "attack")
            local rSource = createMockNode({ recordType = "pc" })
            fAttackSlot(rSource, nil, { sType = "attack" })

            displayProcessAttackFromStealth = fRealDisplay
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

            local fSkillSlot = GameManager.getMultiKeyFunction("onActionPostResolve", "skill")
            local rSource = createMockNode({ recordType = "pc" })
            fSkillSlot(rSource, nil, { sType = "skill", sDesc = "[skill] stealth" })

            displayProcessStealthUpdateForSkillHandlers = fRealDisplay
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
