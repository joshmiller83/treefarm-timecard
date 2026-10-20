# Voice test script

Run this on a real iPhone before each release, three ways: unlocked, locked in a pocket, and over AirPods with the phone locked. Check that the lock-screen Live Activity and (after a sync) the server agree with what Siri said.

Setup: a farm with a field of at least two blocks; you're signed in; you're not clocked in. Times below are spoken the way Siri says them: "7:02" inside the workday (6:00 AM to 5:59 PM), "6:10 PM" outside it.

## The script

| # | Say | Expect Siri to answer | Then check |
|---|---|---|---|
| 1 | "Next row in Time Card" | You're not clocked in. Say "clock in with Time Card" first. | Nothing changed |
| 2 | "Clock in with Time Card" | Clocked in at <time>. You're on block 1, row 1. | Live Activity appears with three row buttons |
| 3 | "Next row in Time Card" | Row 1 marked, <n> trees. Next is row 2. | Row 1 gold on the map; buttons show 2, 3, 4 |
| 4 | "Mark row 3 in Time Card" | Row 3 marked, <n> trees. Next is row 4. | Buttons show 4, 5, 6 |
| 5 | "Mark a row in Time Card" → "12" | Asks: Which row? Then: Row 12 in block 1? That's 8 rows ahead. Say "no" | Okay, nothing marked. Nothing changed |
| 5b | "Mark a row in Time Card" → "999" | Block 1 has rows 1 to <n>. | Nothing changed |
| 6 | "Undo in Time Card" | Undid row 3. | Row 3 open again; buttons show 2, 3, 4 |
| 7 | "Take lunch with Time Card" | Lunch started at <time>. | Activity turns gold, break timer runs |
| 8 | "Take lunch with Time Card" | You're already on lunch since <time>. Say "back to work" when you're done. | Nothing changed |
| 9 | "Back to work with Time Card" | Back at <time>. Lunch was <n> minutes. | Activity green again |
| 10 | "Add a note in Time Card" → "Fuel low on the shears" | Asks: What's the note? Then: Added to today's notes. | Note on today's shift |
| 11 | "Note a tree in Time Card" → "6" → "Leader broken" → "Needs attention" | Asks: Which tree? What's the note? Any flag? Needs attention, dead, replant, or none. Then: Noted on block 1, row <r>, tree 6. | Marker on that tree on the map |
| 12 | "Mark trees in Time Card" → "row 5" → "1" → "6" | Asks: Which row? First tree? Last tree? Then: Marked trees 1 to 6 in row 5. | Six trees gold in row 5 |
| 12b | "Mark trees in Time Card" → "row 15" → "No" | Asks: Which row? Then right away: Row 15 in block 1? That's <n> rows ahead. Then: Okay, nothing marked. (A row more than 5 away or in another block is checked before the trees are asked, as for Mark a row and Note a tree.) | Nothing changed |
| 12c | "Mark trees in Time Card" → "row 40" | Asks: Which row? Then right away: Block 1 has rows 1 to 20. (No tree questions.) | Nothing changed |
| 12d | "Note a tree in Time Card" → "13" | Asks: Which tree? Then right away: Block 1 has 12 trees in each row. (No note is asked for.) | Nothing changed |
| 13 | "I'm in block 2 in Time Card" | Okay, block 2, row 1 is next. | Buttons show block 2 rows |
| 14 | "How long have I worked in Time Card?" | <h> hours <m> minutes today, <x> this week. | Card shows the same |
| 15 | "How many trees in Time Card?" | <n> trees today, <r> an hour. You're on block 2, row 1. | Card shows the same, trees in front |
| 16 | "What row am I on in Time Card?" | You're on block 2, row 1. Next are rows 2 and 3. | Card shows "Row 1, Block 2" large |
| 17 | "What's my pace in Time Card?" | <r> trees an hour today. Your season pace is <s> an hour. | |
| 18 | "How much have I made in Time Card?" (locked) | Unlock your phone to hear your pay. (With "Say pay out loud when locked" on: $<x> today, $<y> this week.) | The card never shows pay while locked unless that setting is on |
| 19 | "How much have I made in Time Card?" (unlocked) | $<x> today, $<y> this week. | |
| 20 | "Fix my start time in Time Card" → "7:30" | Asks: What time did you start? Then: Start time changed to 7:30. | Clock card shows the new start |
| 20b | In the evening, on a shift open since the morning: "Fix my start time in Time Card" → "7:30" | Start time changed to 7:30. (The morning: the 7:30 nearest the shift's start, never 7:30 PM.) | |
| 21 | "Take a break with Time Card" with "Ask for a break reason" on → "Water" | Asks: What's the break for? Then: Break for Water started at <time>. | Break reason on the Live Activity |
| 22 | Airplane mode, then "Next row in Time Card" | Row … marked … (works offline) | Settings shows 1 change waiting; it syncs when back online |
| 23 | Second phone marks a row, then this phone says "Mark row <same> in Time Card" before syncing | After sync: Row … was shaped by <name> on <day>. Next open row is …. | Map shows the other person's mark |
| 24 | Restart the phone; before unlocking it, "Next row in Time Card" | Unlock your phone once, then try again. | Nothing changed |
| 24b | Then unlock the phone, lock it again, and say "Next row in Time Card" | Row … marked … (the app opens its data again; it doesn't need to be restarted) | Live Activity updates |
| 25 | Sign out in Settings, then "Clock in with Time Card" | Open Time Card to sign in. | |
| 26 | "Clock out with Time Card" → "No" | Asks: You've worked <time> today. Clock out? Then: Okay, you're still clocked in. (iOS may say its own "Okay" instead.) | Still clocked in |
| 27 | "Clock out with Time Card" → "Yes" | Clocked out at <time>. <h> hours, <n> trees. | Live Activity ends |

## Every phrase Siri knows

Each command has several ways to say it. Siri needs the app's name in the phrase ("Time Card", or "Tree Card" and "Tree Farm" if it hears it that way). Words in angle brackets are filled in by Siri from the farm.

iOS gives an app ten App Shortcuts, so the status questions share one (the question is the phrase), and so do the less frequent commands under "Notes and Fixes".

- **Clock in:** "Clock in with Time Card", "Clock in on Time Card", "Clock me in with Time Card", "Punch in with Time Card", "Start work with Time Card", "Start my shift with Time Card", "Start my shift in Time Card", "Time Card clock in", "Clock in at <field> with Time Card" ("Clock in at North Field…", "…at the North Field", "…at North"), "Start work at <field> with Time Card".
- **Clock out** (always asks first): "Clock out with Time Card", "Clock out on Time Card", "Clock me out with Time Card", "Punch out with Time Card", "End my shift with Time Card", "End my shift in Time Card", "Stop work with Time Card", "I'm done for the day in Time Card", "Time Card clock out". Answer "yes", "yeah", "sure", "clock out" or "no", "not yet", "cancel".
- **Lunch or a break:** "Take <lunch / a break> with Time Card", "Take <…> in Time Card", "Start <…> in Time Card", "Start <…> with Time Card", "Go on <…> with Time Card", "Going to <…> in Time Card", "<Lunch / Break> time in Time Card", "Take a break with Time Card", "Start a break in Time Card", "Go on break with Time Card". Lunch is also heard as "my lunch", "lunch break"; a break as "break", "my break", "a short break", "a rest".
- **Back to work:** "Back to work with Time Card", "Back to work in Time Card", "End my break in Time Card", "End my break with Time Card", "End lunch in Time Card", "Lunch is over in Time Card", "Break's over in Time Card", "I'm back in Time Card", "Time Card back to work".
- **Next row** (marks the row you're on): "Next row in Time Card", "Next row with Time Card", "Row done in Time Card", "Row done with Time Card", "Done with this row in Time Card", "Finished the row in Time Card", "Mark the next row in Time Card", "Time Card next row", "Time Card row done".
- **A row by number:** "Mark <row 14> in Time Card", "Mark <row 14> with Time Card", "Mark <row 14> done in Time Card", "<Row 14> done in Time Card", "Shaped <row 14> in Time Card", "Finished <row 14> in Time Card". Siri knows the next ten open rows by name; a row in the next block is "row 1 in block 2". "Mark a row in Time Card" or "…with Time Card" asks "Which row?" and takes any number ("fourteen", "row 3 in block 2"). A row more than 5 away, or in another block, is checked first.
- **Move to a block:** "I'm in <block 3> in Time Card", "I'm in <block 3> with Time Card", "Move to <block 3> in Time Card", "Go to <block 3> in Time Card", "Switch to <block 3> in Time Card"; "Change blocks in Time Card" and "Move to another block in Time Card" ask "Which block?".
- **Undo:** "Undo in Time Card", "Undo with Time Card", "Undo that in Time Card", "Undo the last one in Time Card", "Take that back in Time Card", "Time Card undo".
- **Questions** (each with a card): "<question> in Time Card", "<question> with Time Card", "<question> on Time Card", "Ask Time Card <question>", where the question is one of:
  - How am I doing / Status / My status / How's my day going / Give me an update (also "Time Card status" and "Check Time Card")
  - How long have I worked / How many hours have I worked / How many hours / My hours / How long have I been working / Hours today
  - How many trees / How many trees have I done / How many trees today / How many trees have I shaped / My trees / Tree count
  - What row am I on / Where am I / Which row am I on / What's my row / What row is next / What's next
  - What's my pace / How fast am I going / My pace / Trees per hour / What's my speed
  - How much have I made / How much did I make / What have I earned / My pay / How much money have I made / What's my pay
- **Notes and fixes:** "<task> in Time Card", "<task> with Time Card", "<task> on Time Card", where the task is one of:
  - Add a note / Make a note / Take a note / Add a shift note / Note this → "What's the note?"
  - Note a tree / Add a tree note / Flag a tree / Make a note on a tree / Tag a tree → "Which tree?", "What's the note?", "Any flag?" (the row is the one you're on)
  - Mark trees / Mark some trees / Mark part of a row / Mark a few trees → "Which row?", "First tree?", "Last tree?"
  - Fix my start time / Change my start time / I started earlier / Change when I started → "What time did you start?"

A time can't be part of a Siri phrase (App Shortcut phrases can't hold a date or time), so there's no "I started at 7:30 in Time Card": say "Fix my start time in Time Card" and Siri asks "What time did you start?".

All of these, plus Add a Note, Note a Tree, Mark Trees and Fix My Start Time on their own, are in the Shortcuts app under Time Card, ready for the Action button (one press, gloves on: "Next Row" is a good choice).

## How it behaves

- **Locked phone.** Every command runs with the phone locked and never opens the app. The database is readable after the first unlock since a restart; before that, Siri says "Unlock your phone once, then try again." After that unlock the app opens its data again, even if iOS kept it in memory since it woke before the unlock.
- **Is the phone locked?** Time Card asks iOS whether files protected `complete` are readable (`isProtectedDataAvailable`). They're sealed shortly after a phone with a passcode locks, so that's "locked". A phone with no passcode counts as unlocked. Pay is said and shown on a locked phone only with "Say pay out loud when locked" on. The limit: for up to about 10 seconds after locking, or the Require Passcode delay when that's longer, the phone still counts as unlocked, so "How much have I made" asked right after pocketing the phone says the pay.
- **The lock-screen timer.** Every command that changes the day can start the Live Activity from the background (they're Live Activity intents), so "Clock in with Time Card" puts it up with the phone locked, and any later command brings it back if iOS ended it after eight hours or it was swiped away.
- **Nothing is asked when the answer would be no.** Mark trees, notes and fixing the start time check first (signed in, clocked in) so nobody answers three questions only to hear "You're not clocked in."
- **What Siri says** is TreeFarmKit's wording, the same as the lock screen and the app.
- **Lock-screen buttons can't speak.** When a press is refused (the row was shaped by someone else since the screen was drawn), the first sentence of the reason replaces the last action on the Live Activity, with no Undo beside it. A press after clocking out on another phone takes the leftover activity down.
- **Rows and blocks Siri knows by name** follow the farm: the next ten open rows and the twelve blocks nearest you in your field are refreshed when the app opens, when you sign in or out or switch farms, after a sync, and after any row, break or move from Siri, the lock screen or the app.
- **Suggestions.** Using the app's own buttons for clock in, breaks, back to work, rows and moving blocks teaches Siri when you usually do them.

## Checked automatically

`ShortcutsUITests` (UI tests) runs a field day through the Shortcuts app in the simulator: clock in, next row, a row by name, lunch, back to work, how many trees, and clock out with "no" then "yes". `VoiceCommandsTests` and `IntentShellTests` (unit tests) check every command's words, changes and failures against the demo farm, and `ShortcutPhraseTests` checks the built phrase list: every phrase names the app, ten App Shortcuts, one parameter at most.

## Apple Watch

The watch app ships its own ten App Shortcuts (the iPhone's don't run on the watch), and flexible matching is off there, so the phrases below are the whole list: each one ends in "in Time Card" and also exists with "with Time Card". The watch answers with the iPhone's sentence when the phone is in reach; with the phone away, a command waits on the watch and Siri says "Saved on your watch. It'll reach your phone when it's back in range." (docs/watch.md 4.1). Accept the App Shortcuts opt-in the first time: a "no" on watchOS 26 has been reported impossible to undo.

| # | Command | Say (each + "in Time Card" / "with Time Card") | Phone in reach | Phone away |
|---|---|---|---|---|
| W1 | Clock in (opens the app, starts the workout) | Clock in · Punch in · Start work · Start my shift | Clocked in at <time>. You're on block 1, row 1. | Saved on your watch… (the workout starts at once) |
| W2 | Clock out | Clock out · Punch out · End my shift · Stop work | Asks: You've worked <time> today. Clock out? Then the phone's sentence | Asks the same; then Saved on your watch… |
| W3 | Lunch | Take lunch · Start lunch | Lunch started at <time>. | Saved on your watch… |
| W4 | A break | Take a break · Start a break | Break started at <time>. | Saved on your watch… |
| W5 | Back to work | Back to work · End my break | Back at <time>. Lunch was <n> minutes. | Saved on your watch… |
| W6 | Next row | Next row · Row done · Mark the next row | Row 14 marked, <n> trees. Next is row 15. | Saved on your watch…; with no row the watch knows: Out of rows the watch knows. Bring your phone closer. |
| W7 | A row by number | Mark <row> · <row> done; "Mark a row" asks "Which row?" | Row 14 marked…; a row more than 5 away or in another block asks first | Asks the same; then Saved on your watch… |
| W8 | Undo | Undo · Undo that | Undid row 14. | A tap still waiting: Took back row 15. It wasn't sent yet. Otherwise: Undo needs your phone nearby. |
| W9 | Status | How long have I worked · How many trees · What row am I on · What's my pace | One answer covering all four, from the phone | The same from the watch, with "as of <time>" |
| W10 | A note | Add a note | Asks: What's the note? Then: Added to today's notes. | Asks the same; then Saved on your watch… |

**W7 by voice, two ways (record which works on the Ultra 2):** say "Mark row 40 in Time Card" directly, and also "Mark a row in Time Card", then "forty" when Siri asks "Which row?". Watch phrases need an exact match, and a parameterized phrase is filled only from the rows the watch suggests (`suggestedEntities()`, the first 10 rows it shows), so the direct phrase may match only when row 40 is one of them. The second path reads the spoken number (`entities(matching:)`), which the watch tests cover.

Watch checks: with no state yet, every command says "Open Time Card on your iPhone once." Signed out on the phone: "Open Time Card on your iPhone to sign in." Pay, moving blocks, tree notes and the start time are phone-only (raise the phone or use AirPods).
