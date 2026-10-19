# Voice test script

Run this on a real iPhone before each release, three ways: unlocked, locked in a pocket, and over AirPods with the phone locked. Check that the lock-screen Live Activity and (after a sync) the server agree with what Siri said.

Setup: a farm with a field of at least two blocks; you're signed in; you're not clocked in.

| # | Say | Expect Siri to answer | Then check |
|---|---|---|---|
| 1 | "Next row in Time Card" | You're not clocked in. Say "clock in with Time Card" first. | Nothing changed |
| 2 | "Clock in with Time Card" | Clocked in at <time>. You're on block 1, row 1. | Live Activity appears with three row buttons |
| 3 | "Next row in Time Card" | Row 1 marked, <n> trees. Next is row 2. | Row 1 gold on the map; buttons show 2, 3, 4 |
| 4 | "Mark row 3 in Time Card" | Row 3 in block 1 marked. | Buttons show 2, 4, 5 |
| 5 | "Mark row 40 in Time Card" | Asks: Row 40 in block 1? That's … rows ahead. Say "no" | Nothing changed |
| 6 | "Undo in Time Card" | Undid row 3. | Row 3 open again |
| 7 | "Take lunch with Time Card" | Lunch started at <time>. | Activity turns gold, break timer runs |
| 8 | "Take lunch with Time Card" | You're already on lunch since <time>… | Nothing changed |
| 9 | "Back to work with Time Card" | Back at <time>. Lunch was <n> minutes. | Activity green again |
| 10 | "Add a note in Time Card" → "Fuel low on the shears" | Added to today's notes. | Note on today's shift |
| 11 | "Note a tree in Time Card" → row, tree, "leader broken", flag "needs attention" | Noted on row <r>, tree <t>. | Marker on that tree on the map |
| 12 | "I'm in block 2 in Time Card" | Okay, block 2, row 1 is next. | Buttons show block 2 rows |
| 13 | "How long have I worked in Time Card?" | <h> hours <m> minutes today, <x> this week. | |
| 14 | "How many trees in Time Card?" | <n> trees today, <r> an hour. You're on block 2, row 1. | Snippet card shows the same |
| 15 | "How much have I made in Time Card?" (locked) | Unlock to hear your pay, unless "Say pay out loud when locked" is on | |
| 16 | "I started at 7:30 in Time Card" | Start time changed to 7:30. | Clock card shows the new start |
| 17 | Airplane mode, then "Next row in Time Card" | Row … marked … (works offline) | Settings shows 1 change waiting; it syncs when back online |
| 18 | Second phone marks a row, then this phone says "Mark row <same> in Time Card" before syncing | After sync: Row … was shaped by <name> on <day>. | Map shows the other person's mark |
| 19 | "Clock out with Time Card" → "No" | Okay, you're still clocked in. | Still clocked in |
| 20 | "Clock out with Time Card" → "Yes" | Clocked out at <time>. <h> hours, <n> trees. | Live Activity ends |
