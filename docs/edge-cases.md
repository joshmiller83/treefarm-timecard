# Edge cases

Each line here has a test, written before the code it covers. The test name is in brackets once the test exists.

## Time
- Daylight saving days (23 and 25 hours) in the farm's time zone; week bounds still land on midnights.
- A shift across midnight counts toward the day it started (as the original web time card did).
- A shift across the pay-week boundary counts toward the week it started.
- Monday vs Sunday week starts.
- Device clock ahead of the server: the server allows 5 minutes of skew.
- An open shift from yesterday shows "worked this shift" with a warning.
- A shift open more than 16 hours prompts a "forgot to clock out?" fix.
- A closed shift can't be longer than 24 hours; a zero-length shift is refused.

## Shifts and breaks
- Overlapping shifts, including overlap with the shift that's still open.
- Overlapping breaks; a break outside its shift; only the latest break may be open.
- Clocking out during a break closes the break at the same moment.
- Moving the open shift's start after its first break, or into the future, is refused.
- Deleting a shift that has marked trees warns with the count and removes those marks.
- Two phones clock in offline at once: the server keeps the first and returns it to the second.
- A later raise doesn't change past pay (each shift keeps its own rate).

## Fields, blocks and trees
- A field with no blocks; 1×1 and 300×300 blocks; mixed across/down blocks.
- Strips of different heights; gaps in grid column numbers.
- The next three rows cross into the next block and the next strip, wrap once to rows left behind, count partly shaped rows as open, and come back empty when the field is done.
- A tree shaped on someone else's shift is never removed or overwritten by your edits.
- Two people mark the same tree at once: first write wins, and the other phone says who and when.
- A resize, move or delete that would strand marks or notes is refused.
- Last year's marks don't show on this season's map; notes do.

## Sync and accounts
- Days offline, then hundreds of changes pushed in batches.
- A push retried after a timeout is applied once.
- A pull while edits are waiting keeps the local edits.
- A token that expires while offline keeps every local change and asks to sign in again.
- Expired or used invite codes; a mistyped code with dashes or lowercase letters still works.
- The last admin can't demote or remove themself.
- A removed member's hours stay, but they can't sign in to that farm.
- Login rate limits and a 15-minute lock after repeated failures.

## Lock screen and voice
- Live Activity buttons pressed while the phone is locked.
- iOS ends Live Activities after 8 hours: a reminder comes at 7 h 50 m, and the activity restarts when the app opens.
- Live Activities turned off in Settings.
- A row shaped by someone else between showing the button and tapping it.
- Siri before the first unlock after a reboot.
- Two voice commands back to back, faster than a sync.
- A spoken row far from where you are ("forty" heard for "fourteen") asks before marking.
- "Next row" when the next open row is in another block says the block out loud.
- Answering "no" to the clock-out question changes nothing.
- Undo never crosses a shift: clocking in or out clears it, and it refuses anything changed since (deleted in the Log, fixed by an admin, refused by the server) [clockingOutForgetsWhatCouldBeUndone, undoCantReviveAShiftDeletedInTheLog, undoKeepsAnAdminFixThatArrivedBySync].
- A dictated note over the length limit is trimmed, and Siri says so.
- Pay is spoken on a locked phone only if you turned that on.
