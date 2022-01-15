# StealthTracker

StealthTracker v3.5 by Justin Freitas

ReadMe and Usage Notes

StealthTracker is a Fantasy Grounds (Classic or Unity) v3.3.15+, 5e ruleset based extension that tracks PC and NPC stealth rolls in combat and provides various notifications to the GM as to how the current Combat Tracker actor's stealth score compares to the passive perception of other actors, and also, if the current actor can see others that are hiding/stealthing.  This works by comparing the Passive Perception of the current actor (character sheet for PC, CT sheet for NPC) against any tracked stealth roll value for the other CT actors.  The stealth roll value for the various CT actors is tracked as an effect on the CT actor with the syntax "Stealth: #".  If an NPC sheet doesn't have the "senses" sheet entry with an embedded "passive Perception #" value (case sensitive), then the value will be computed as 10 + wisdom bonus.  If the NPC sheet is lacking a Stealth skill to roll, it will be added as "Stealth +0" line in their skills section of the sheet (on the Combat Tracker node only, not main NPC sheet). For a PC sheet, the passive perception is taken from the field, which always has a value.

When a Stealth skill roll is rolled on an actors turn in combat, the stealth roll will automatically be added to the effects of that Combat Tracker actor.  This only happens when combat is active (there is an active actor in the CT).  Also, players are restricted from the effects update when it's not their turn in combat (DM can always drag their roll to their CT entry to process the Stealth value).  When a Stealth effect is added to a CT actor, it's now added with no duration and will be expired (configurable option) by actions like an attack, a cast, a cast save, spell attack, etc.  When the initiative is cleared (via the Combat Tracker menu), all stealth data will be removed from the CT actor names automatically (same functionality as '/stealth clear' chat command). At any time, the manual approach of editing combat tracker effects will still work for updates.

For StealthTracker to work properly, proper Fantasy Grounds use is required.  For example, at the end of combat, clear the initiative via the Combat Tracker menu.  That way, all CT actors will get scrubbed of StealthTracker data.  It prepares the system for next encounter also by firing the TurnStart event when you press the Next Actor button in the Combat Tracker to begin the encounter.  Simply placing the initiative pointer on an actor in the Combat Tracker will not fire the necessary events for StealthTracker to work properly.  In this case, you can force the check telling who is hidden from the current actor ("does not perceive") by using the chat command "/stealth".  The st command will also show what targets are unaware of the current actor (potentially allowing for Advantage on an attack roll).  Any Stealth roll for a non-visible npc current actor in the CT will automatically be made in the tower so that it's not clear what's going on with the hidden actor, even if the setting to show DM rolls is on.

The host/DM can issue a "/stealth clean" command to reset all of the actors in the CT.

Known Limitations:
- The StealthTracker hidden check will only fire when the actor's turn is started via the CT DownArrow/NextTurn button.  Dragging the turn pointer to a new actor will not trigger the checks.
- In a multi-target attack from stealth (like maybe a twinned spell attack from a sorcerer or something similar), only the first roll is accounted for in the analysis.
- With script, I can't force a dice roll into the tower.  Maybe this is possible some other way, but right now, I can only trap the condition and put a chat message up to have the player roll in the tower (only applicable when the 'None' value is selected for the 'Player: Show Stealth info' option) and then ignore that particular roll.
- When StealthTracker processes a Hide action from the Generic Actions extension, the effect is assigned before the roll output is displayed.  With a normal Stealth roll, the effect is assigned afterwards.  Not an issue but a difference worth noting.

Future Enhancements:
- Consider removing or making optional the restriction that a player can only update the PC or NPC they are controlling when it's that actor's turn in the CT.
- Incorporate light/distance (FGU only)

Changelist:
- v1.1 - The main purpose of the new version is to incorporate a chat command that displays all of the visible actors in the battle and WHO THEY CAN'T PERCEIVE.
- v1.2 - Added auto application of stealth rolls to the Character/CT sheet names, support for npc sheets shared to players, clearing of StealthTracker data (via clearing initiative in CT or by '/stealth clear'), fixes for all of the hidden actor scenarios where chat messages are secret when a hidden npc is involved, many general fixes and performance improvements.
- v1.2.1 - Bugfix for the substring search looking for the stealth roll.
- v1.3 - Added the ability to drag stealth rolls from the chat to a CT actor for name update with stealth value from roll.  This works only for host/DM and it can be dropped on any character (no name validation). Added checks on attack to see if the attacker can see the target (is attack even possible?) and to see if the target can see the attacker (ADVATK).
- v2.0 - This was a major change to move from tracking stealth in the actor's name to tracking stealth in the actor's effects list.  This helped to eliminate several limitations that were a side effect of overloading the actor name field.
- v2.1 - Update to account for 3.3.13.
- v2.2 - Deprecation updates.  Addition of current CT actor name to the 'not stealthing' message for clarity. Update to account for 3.3.14.
- v2.3 - Bug fixes and protection from null pointer exceptions.
- v2.4 - Change to the action handler override mechanism to chain in the override instead of always calling the base.  This should work around the compatibility issues with other extensions.
- v2.5 - Extension name change to comply to standard convention, change load order to 999, do not assess stealth attack if target is hidden.
- v2.6 - Make the Stealth effect hidden for non friendly npcs.  No duration on stealth effects, per rules... it should last until something stops it. NPE protections from manager calls.  Comment cleanup.  Refactor common logic.
- v2.7 - Expire stealth in more places now that it doesn't have a duration.  This includes spell casts, spell attacks, spell saves, power saves from the actions tab.  I wired a new handler for this: onCastSave.  Stealth processing only occurs for spell attack rolls.  Fixed an NPC passive perception leak to the players when attacking from stealth without advantage, now the message is local to GM only.  Change to have GM own all effects on CT nodes so that users can't change their attributes (like make it inactive).  Report to the GM only that an attack was made from stealth even if the target sees the attacker (previously a no op).
- v2.8 - Added an option to allow for broadcast of some StealthTracker info to clients, but it defaults to Off.  It does leak passive perception of monsters which is why it defaults to off.   No more user chat commands, only DM.  Some minor refactoring for cleanliness. Fixed several bugs in the code for expiration of Stealth effect by having all Stealth processing occur on the host only.  The clients will only sent an OOB message when they need processing.  Added an option to expire the Stealth effect with a duration (it's a duration of 2 with the effect init set to tick on current - .1) which defaults to On.
- v2.9 - When the CT is advanced to the turn of a NPC, if the NPC doesn't already have Stealth in its Skills section, it will be added with a zero modifier so that it is easy to stealth with the NPC on its turn.
- v2.9.1 - Bug fix for error when there is no Skills node on the NPC sheet.
- v3.0 - This new version supports completely hiding all StealthTracker information (StealthTracker chat messages & StealthTracker effect display) from players.  This way, tables that keep all stealth values hidden won't leak any of the information to the players.  See the new 'Player: Show Stealth info' option in the settings, it's tri-state now (was the old broadcast flag).  Now filters out CT nodes that don't have a type set (often used by DMs for a quick CT entry for a trap or something).  Many refactors for correctness and optimization.  Special thanks to Raddu for the suggestions!
- v3.1 - Migration to FGU conventions (i.e. launch message to announcement text, etc).  Changed the chat command(s) from 'st' or 'stealthtracker' to only 'stealth' due to conflicts between 'st' and 'story' in FGU.
- v3.2 - In any NPC CT actor sheet that is modified to have a Stealth skill, it now accounts for the NPC's dexterity modifier (thanks Ludd_G for the suggestion).  Expanded the Stealth effect expiration options (from on/off) to be None, Action, Action and Round (thanks Ludd_G for the suggestion).
- v3.2.1 - Fix and protection against null pointer exception reported by UnlivingLuke.
- v3.2.2 - Fix to account for all dice in the stealth skill roll when computing total for effect.
- v3.2.3 - Improve dice check in skill handler by using common code.
- v3.3 - Use looked up, translated strings for 'Stealth' and 'Dexterity' so that the StealthTracker functionality will work for localized rulesets.  Thanks to shoebill for the suggestion.
- v3.4 - Added support for the Generic Action extension Hide action to be processed like Stealth rolls are.  Thanks to BushViper and plap3014 for the suggestion and SilentRuin for support.
- v3.4.1 - Decode adv/disadv in the post roll handler for the Generic Actions extension compatibility before using the roll total to assign a Stealth effect.  Special thanks to Ludd_G for the bug report.
- v3.4.2 - Account for a change in FG CT onAdd handler behavior and don't assign the NPC sheet Stealth skill at that time due to uninitialized attributes.  Do it onTurnStart instead where the attributes are correct until the issue with FG is resolved.  Thanks again to Ludd_G for the report.
- v3.4.3 - Various refactoring and improvement in the code, such as utilization of common FG functions to accomplish tasks instead of homegrown logic.
- v3.4.4 - Fix for camel cased typo in gmatch function call.  Thanks to carrierpl for the report.
- v3.4.5 - gmatch was a mistake entirely, revert to gsub
- v3.5 - Bug fix for incorrect stat reporting in attack from stealth scenario.  Don't process stealth on debilitated actors or actors of the same faction as the one being analyzed.  Massive reduction in chat verbosity.  Thanks to Ludd_G for the suggestions and inspiration.

![alt text](https://github.com/JustinFreitas/StealthTracker/blob/master/graphics/StealthTrackerScreenshot.jpg?raw=true)
