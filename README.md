# StealthTracker

StealthTracker v1.2 by Justin Freitas

ReadMe and Usage Notes

StealthTracker is a simple FG v3.X, 5e ruleset based extension that notifies the chat of the Combat Tracker actors that are not perceptible by the current CT actor due to being hidden.  This works by comparing the Passive Perception of the current actor (character sheet for PC, CT sheet for NPC) against any tracked stealth roll value for the other CT actors.  The stealth roll value for the various CT actors is tracked in the CT actor name field by appending the stealth roll value prefixed by lower case 's'.  For example, if the actor name is "Zeus" and the stealth roll was 16, the stealth tracked CT name would be "Zeus - s16".  Note that the dash is optional, but there must be at least one space between the name and the s## string.  Thus, "Zeus s16" would also work.  If a NPC sheet doesn't have the "senses" sheet entry with an embedded "passive Perception ##" value (case sensitive), then stealth tracking will not operate for that actor.  For a PC sheet, the PP is taken from the field, which always has a value.  I chose to use the name field to track the stealth because it had the least impact on the ruleset and also because the PC can very easily update their character sheet.  I noticed that modifiying only the CT record for PCs didn't save its state from host session to session, whereas, that data is persisted in the character sheet record.

With version 1.2+ of the extension, the stealth roll will automatically be added to the name field of the character sheet (for PC) or the name field of the CT sheet (for NPC).  This only happens when combat is active (there is an active actor in the CT).  Also, players are restricted from the automatic name update when it's not their turn in combat.  When an actor's turn is reached, any existing stealth tracking will be removed, as they will need to stealth again to continue hiding.  When the initiative is cleared (via the CT menu), all stealth data will be removed from the CT actor names automatically (same functionality as '/st clear' chat command). At any time, the manual approach of editing character or PC names will still work for updates.

One thing to remember is that you don't have to type the entire character name when whispering.  Tab key autocompletion works when there are enough characters to make a unique choice.  That's good to know considering that StealthTracker modifies the character name.  Also, for StealthTracker to work properly, proper Fantasy Grounds use is required.  For example, at the end of combat, clear the initiative via the Combat Tracker menu.  That way, all actor names will get scrubbed of StealthTracker data.  It prepares the system for next encounter also by firing the TurnStart event when you press the Next Actor button in the Combat Tracker to begin the encounter.  Simply placing the initiative pointer on an actor in the Combat Tracker will not fire the necessary events for StealthTracker to work properly.  Any Stealth roll for a non-visible npc current actor in the CT will automatically be made in the tower so that it's not clear what's going on with the hidden actor, even if the setting to show DM rolls is on.

The host/DM can issue a "/st clean" command to reset all of the names in the CT.

Known Limitations:
- If there is a stealth tracked name set, using that CT actor entry to make new CT entries might throw off the auto duplicate NPC counting scheme of Fantasy Grounds.  In this particular case, drag new NPCs in from the Encounter or the NPC collection in FG.
- The StealthTracker hidden check will only fire when the actor's turn is started via the CT DownArrow/NextTurn button.  Dragging the turn pointer to a new actor will not trigger the checks.

Future Enhancements:
- Investigate tracking of the stealth value in some other spot than the actor name.  Need to figure out a convenient and visible mechanism to do so.  Maybe this gets tracked as an effect.  Or maybe as a custom CT field.
- Consider removing or making optional the restriction that a player can only update the PC or NPC they are controlling when it's that actor's turn in the CT.

Changelist:
v1.1 - The main purpose of the new version is to incorporate a chat command that displays all of the visible actors in the battle and WHO THEY CAN'T PERCEIVE.
v1.2 - Added auto application of stealth rolls to the Character/CT sheet names, support for npc sheets shared to players, clearing of stealthtracker data (via clearing initiative in CT or by '/st clear'), fixes for all of the hidden actor scenarios where chat messages are secret when a hidden npc is involved, many general fixes and performance improvements.