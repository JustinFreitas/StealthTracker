https://github.com/JustinFreitas/StealthTracker



WARNING:

This extension is incompatible with any other extension that overrides the skill or attack handlers.  There are probably many out there, so as I hear about them, I'll add them to the list.  I recommend you uninstall StealthTracker and use the other extension instead, in most cases.  Here are the extensions that StealthTracker is confirmed to not work with:

5e - Automatic Halfling Luck



StealthTracker v2.3 by Justin Freitas

ReadMe and Usage Notes

StealthTracker is a Fantasy Grounds (Classic or Unity) v3.3.15+, 5e ruleset based extension that notifies the chat of the Combat Tracker actors that are not perceptible by the current CT actor due to being hidden.  This works by comparing the Passive Perception of the current actor (character sheet for PC, CT sheet for NPC) against any tracked stealth roll value for the other CT actors.  The stealth roll value for the various CT actors is tracked as an effect on the CT actor with the syntax "Stealth: XX".  If a NPC sheet doesn't have the "senses" sheet entry with an embedded "passive Perception ##" value (case sensitive), then the value will be computed as 10 + wisdom bonus.  For a PC sheet, the PP is taken from the field, which always has a value.  I chose to use the name field to track the stealth because it had the least impact on the ruleset and also because the PC can very easily update their character sheet.  I noticed that modifying only the CT record for PCs didn't save its state from host session to session, whereas, that data is persisted in the character sheet record.

With version 1.2+ of the extension, the stealth roll will automatically be added to the name field of the character sheet (for PC) or the name field of the CT sheet (for NPC).  This only happens when combat is active (there is an active actor in the CT).  Also, players are restricted from the automatic name update when it's not their turn in combat.  When an actor's turn is reached, any existing stealth tracking will be removed, as they will need to stealth again to continue hiding.  When the initiative is cleared (via the CT menu), all stealth data will be removed from the CT actor names automatically (same functionality as '/st clear' chat command). At any time, the manual approach of editing combat tracker effects will still work for updates.

For StealthTracker to work properly, proper Fantasy Grounds use is required.  For example, at the end of combat, clear the initiative via the Combat Tracker menu.  That way, all CT actors will get scrubbed of StealthTracker data.  It prepares the system for next encounter also by firing the TurnStart event when you press the Next Actor button in the Combat Tracker to begin the encounter.  Simply placing the initiative pointer on an actor in the Combat Tracker will not fire the necessary events for StealthTracker to work properly.  In this case, you can force the check telling who is hidden from the current actor ("does not perceive") by using the chat command "/st".  Additionally, the DM can issue the "/st unaware" command to show what targets are unaware of the current actor (potentially allowing for Advantage on an attack roll).  Any Stealth roll for a non-visible npc current actor in the CT will automatically be made in the tower so that it's not clear what's going on with the hidden actor, even if the setting to show DM rolls is on.

The host/DM can issue a "/st clean" command to reset all of the actors in the CT.

Known Limitations:
- The StealthTracker hidden check will only fire when the actor's turn is started via the CT DownArrow/NextTurn button.  Dragging the turn pointer to a new actor will not trigger the checks.

Future Enhancements:
- Consider removing or making optional the restriction that a player can only update the PC or NPC they are controlling when it's that actor's turn in the CT.
- Consider adding 'Stealth+0' to the Skills of NPCs if it doesn't exist to make their skill checks easier to process.  Or in a more complex case, have a custom stealth button on the sheet.

Changelist:
- v1.1 - The main purpose of the new version is to incorporate a chat command that displays all of the visible actors in the battle and WHO THEY CAN'T PERCEIVE.
- v1.2 - Added auto application of stealth rolls to the Character/CT sheet names, support for npc sheets shared to players, clearing of StealthTracker data (via clearing initiative in CT or by '/st clear'), fixes for all of the hidden actor scenarios where chat messages are secret when a hidden npc is involved, many general fixes and performance improvements.
- v1.2.1 - Bugfix for the substring search looking for the stealth roll.
- v1.3 - Added the ability to drag stealth rolls from the chat to a CT actor for name update with stealth value from roll.  This works only for host/DM and it can be dropped on any character (no name validation). Added checks on attack to see if the attacker can see the target (is attack even possible?) and to see if the target can see the attacker (ADVATK).
- v2.0 - This was a major change to move from tracking stealth in the actor's name to tracking stealth in the actor's effects list.  This helped to eliminate several limitations that were a side effect of overloading the actor name field.
- v2.1 - Update to account for 3.3.13.
- v2.2 - Deprecation updates.  Addition of current CT actor name to the 'not stealthing' message for clarity. Update to account for 3.3.14.
- v2.3 - Bug fixes and protection from null pointer exceptions.