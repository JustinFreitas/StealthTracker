StealthTracker v1.0 by Justin Freitas

ReadMe and Usage Notes

StealthTracker is a simple FG v3.X, 5e ruleset based extension that notifies the chat of the Combat Tracker actors that are not perceptable due to being hidden.  This works by comparing the Passive Perception of the current actor against any tracked stealth roll value for the other CT actors.  The stealth roll value for the various CT actors is tracked in the CT actor name field by appending the stealth roll value prefixed by lower case 's'.  For example, if the actor name is "Zeus" and the stealth roll was 16, the stealth tracked CT name would be "Zeus - s16".  Note that the dash is optional, but there must be at least one space between the name and the s## string.  Thus, "Zeus s16" would also work.  If a NPC sheet doesn't have the "senses" sheet entry with an embedded "passive Perception ##" value (case sensitive), then stealth tracking will not operate for that actor.  For a PC sheet, the PP is taken from the field, which always has a value.

Known Limitations:
- If there is a stealth tracked name set, using that CT actor entry to make new CT entries might throw off the auto duplicate NPC counting scheme of Fantasy Grounds.  In this particular case, drag new NPCs in from the Encounter or the NPC collection in FG.
- The StealthTracker hidden check will only fire when the actor's turn is started via the CT DownArrow/NextTurn button.  Dragging the turn pointer to a new actor will not trigger the checks.

Future Enhancements:
- Tracking of the stealth value in some other spot than the actor name.  Need to figure out a convenient and visible mechanism to do so.
- Automatic tracking of stealth value on a stealth skill roll.