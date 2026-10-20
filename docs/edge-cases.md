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
- A clock-in left open for days: Clock out (and Siri) checks the same rules as the server and points to the Log; the Clock tab's button becomes "Fix clock-out time", which opens the shift with a clock-out filled in from the last break or tree [clockingOutAfter25HoursPointsToTheLog, fixingAClockOutLeftOpenForDaysFillsInTheLastWork].

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
- A token that expires while offline keeps every local change and asks to sign in again; someone else signing in over unsynced work is refused before anything is wiped [signingInAgainAsSomeoneElseCantWipeUnsyncedWork].
- A clock-in refused because a shift is already open moves its trees to that shift; only a lost tree drops the local copy [aRefusedClockInKeepsItsCopyAndMovesItsTreesToTheOpenShift].
- A role change pulls the farm again under the new role; a demoted admin's phone forgets other people's shifts [aPromotedWorkerGetsEveryonesHoursAndRealRates, aDemotedAdminsPhoneForgetsOtherPeoplesHours].
- Signing out waits for a sync on its way and sends waiting changes first [signingOutDuringASlowPullLeavesNothingBehind, signingOutRightAfterASaveSendsItFirst].
- An edit is stamped after the version it replaces, even when this phone's clock is behind [anEditIsAlwaysAfterWhatItReplaces].
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
- "Next row" when the next open row is in another block says the block out loud, including when a sync shaped the rest of your block [nextRowSaysTheBlockWhenASyncMovedYou].
- Answering "no" to the clock-out question changes nothing.
- Undo never crosses a shift: clocking in or out clears it, and it refuses anything changed since (deleted in the Log, fixed by an admin, refused by the server) [clockingOutForgetsWhatCouldBeUndone, undoCantReviveAShiftDeletedInTheLog, undoKeepsAnAdminFixThatArrivedBySync].
- A dictated note over the length limit is trimmed, and Siri says so.
- Pay is spoken on a locked phone only if you turned that on.

## Apple Watch
The full behaviour is in [watch.md](watch.md) section 6. Test names are in brackets; UI tests start with `test`.

### Taps that wait for the phone
- Phone out of reach, then back: taps queue with the time they were made and the shift on screen, the screen keeps showing them (row 16 next with 14 and 15 waiting, even after a state push), and they flush oldest first, one at a time [outOfReachTheTapIsQueuedWithItsTimeAndShift, aNewStateWithTwoQueuedMarksStillShowsRow16, reachabilityComingBackFlushesTheOutbox, oneRequestInFlightAtATimeInOrder, testTapsWaitOutOfReachAndFlushWhenThePhoneIsBack]. The phone applies each at its tap time, stamped when it arrived [theEventTimeIsTheTapAndUpdatedAtIsWhenItArrived, aTapFromTheFutureCountsWhenItArrived].
- A queued mark counts its row's open trees in "Block 2 · N trees" and in the field, never past its total [aMarkCountsTheTreesItsRowWouldShape, aMarkNeverCountsTheFieldPastItsTotal, eachChipCarriesTheTreesItsMarkWouldShape].
- More than 40 rows marked out of reach: "Out of rows the watch knows. Bring your phone closer.", never "Field done" unless the field is shaped [noChipQueuesNothingAndSaysOutOfKnownRows, noChipQueuesNothingAndSaysFieldDone, runningOutOfChipsAwayFromThePhoneIsNotFieldDone].
- The phone app in the background with its database suspended: the tap still applies, the reply and state go out, and the revisions keep counting up [aTapThatReachesThePhoneInAPocketStillApplies, inAPocketTheTapIsSentOnAndTheDatabaseLetGoOnceItsStateHasGoneOut, onScreenTheDatabaseIsNeverLetGo, aPublishOfAnotherDoorsChangeLeavesTheDatabaseAlone, aCounterThatCantBeSavedNeverRepeatsARevision, anEmptyStoreThatCantBeWrittenKeepsOneEpoch, theCounterCarriesOnOnceItCanBeSavedAgain, twoDesksOnOneStoreShareTheCounter].
- A queued clock-out that reaches the phone after a new phone clock-in is refused, naming the old shift [aQueuedClockOutAfterANewPhoneClockInIsRefused].
- Queued row marks from a closed shift are refused with the shift named, and listed on the watch for an hour [marksFromAClosedShiftAreRefused, aTapForAShiftWhenNoneIsOpenSaysSo, aQueuedTapRefusedLaterIsListedForAnHour].
- A queued clock-in older than the last closed shift's end is refused [aClockInOlderThanTheLastShiftsEndIsRefused].
- A watch clock-in queued while the phone already clocked in: its minted id is aliased to the open shift, the marks after it apply, and the workout is retagged [aRefusedClockInAliasesItsIdSoLaterMarksApply, theAliasSurvivesANewDeskOnTheSameStore, aRefusedWatchClockInIsRememberedForTheWorkout, alreadyOpenRetagsTheRefusedClockIn].
- A reply lost on the way back: the tap stays queued and is sent again, the phone answers the retry from its inbox, and the next state's applied ids clear it [aDurableTapSurvivesALostReplyAndAStateWithItsIdClearsIt, aDuplicateRunsOnceAndTheRetryGetsAFreshState, appliedIdsArentAppliedTwice].
- A reply after the 4 s timeout is ignored and the retry is deduplicated [aLateReplyAfterTheTimeoutIsIgnoredAndTheRetryIsDeduped].
- A flushed clock-in's answer and the phone's state arrive in one change, so the workout never sees the clock-in answered while the old off-the-clock state is still held [aFlushedClockInsStateArrivesWithItsAnswer, theSnapshotThatDropsATapCarriesItsReplysState].
- A queued tap the phone's state has moved past gets the engine's sentence [aQueuedTapThePhoneMovedPastGetsTheEnginesSentence].
- A queued end of break earlier than the break's start ends it at the start, never before [aQueuedEndOfBreakNeverLandsBeforeTheBreakStarted].
- Past 200 waiting taps the oldest row marks are dropped and counted; clock and break changes never are [pastTheLimitTheOldestRowTapsAreDroppedAndCounted].
- While the phone can't run taps (apps out of step, its store not open), every tap says why instead of "Saved on watch" [whileThePhoneCantRunTapsEveryTapSaysWhy, onceThePhoneRunsTapsAgainTheSavedLineIsBack, aReplyTheWatchCantReadKeepsTheTapAndSaysUpdate].
- During a workout session the outbox is tried every minute, and only then [duringASessionTheOutboxIsTriedEveryMinute, withoutASessionTheOutboxWaitsForTheNextChance].

### The phone and the link
- The iPhone app killed or never launched: a watch message wakes it and waits for it to start, so there's no false "sign in" [aRequestThatWakesTheAppWaitsForItToStart].
- Phone reinstalled, a new phone or a store reset: a new epoch, and the watch takes its lower revisions; an older revision in the same epoch is ignored [anEmptyStoreStartsANewEpoch, theRevisionAndEpochPersistAcrossANewDesk, aNewEpochWithALowerRevisionIsAccepted, anOlderRevisionInTheSameEpochIsIgnored].
- Phone restarted and not yet unlocked: the tap stays queued and the watch says "Unlock your phone once."; once unlocked the phone opens its data and applies it [aPhoneThatCantReadItsDataKeepsTheTapQueuedWithNoState, aSealedPhoneKeepsTheTapQueuedAndSendsNoState, aSealedPhoneUnlockedSinceOpensItsDataAndAppliesTheTap, aSealedPhoneWhoseDataStillWontOpenKeepsTheTapQueued, aTapQueuedWhileThePhoneNeedsUnlockingSaysSo].
- Siri clocks in on the phone while the watch sleeps: the context goes first, then `startWatchApp`; a watch launched before the state arrives starts untagged and tags it later, and a stale off-the-clock state doesn't discard it [aPhoneClockInStartsTheWatchWorkoutAfterTheContext, noWorkoutLaunchForAWatchClockIn, noWorkoutLaunchWithRecordingOff, noWorkoutLaunchForOtherChanges, aPhoneLaunchBeforeTheStateArrivesStartsUntaggedNow, staleOffClockContextRightAfterAPhoneLaunchNoDiscard, aPhoneLaunchStartsInTheBackgroundThenTagsWhenTheStateArrives, aLaunchThatNeverAnswersTimesOut].
- A phase change the watch can't hear goes as a complication push while the budget lasts; the watch handles it like a context, and a background wake ends only once it's handled [aPhaseChangeOutOfReachPushesTheComplicationWhileBudgetLasts, noComplicationPushWhileTheWatchIsInReach, aUserInfoEventIsHandledLikeAContextAndDrainedWaitsForIt, aBackgroundWakeEndsOnlyOnceTheDeliveredStateIsHandled].
- A watch that never heard from the phone refuses every command before queueing: "Open Time Card on your iPhone once." [withNoStateEveryCommandIsRefused, tapsWithNoPersonCountAsSomeoneElse, clockInWithNoStateQueuesNothing, nextRowWithNoStateOrSignedOut].
- A Siri cold launch on the watch starts from the last state it saved, not "Open Time Card on your iPhone once." [theConfirmedStateSurvivesARelaunch, observersHearTheRestoredStateWhenTheModelStarts].
- Signed out on the phone: waiting taps stay and apply if the same person signs in; someone else's are dropped with a sentence [signedOutKeepsTheTapQueuedAndItAppliesAfterSigningIn, tapsForSomeoneElseAreNotApplied, tapsForSomeoneUnknownAreNotApplied, aSignedOutPhoneRefusesNewTapsAndKeepsTheWaitingOnes, signingOutOnThePhoneLeavesTheWorkoutAlone].
- An older or newer app on one side: the reply says which to update and the tap stays queued [anUndecodableEnvelopeGetsAnUnreadableReplyWithState, aNewerEnvelopeGetsTheSameAnswer, everyRequestIsAnsweredExactlyOnce, aReplyTheWatchCantReadKeepsTheTapAndSaysUpdate].
- `recordWorkouts` turned off mid-shift: the next state says so and the running workout finishes now [aSettingsChangeShowsInTheNextState, turningRecordingOffPublishesTheNewSetting, recordingTurnedOffMidShiftFinishesTheRunningWorkoutNow, recordingTurnedOffMidShiftFinishesNow].

### Gloves, Siri and the Action button
- Double Tap twice fast marks row 14 and then row 15 [twoQuickTapsMarkTwoRows, twoMarksInARowMoveTwoChips, nextRowSendsTheChipShownNeverMarkNextRow]. The simulators have no hand gestures, so the Double Tap UI test skips and the device checks it [testDoubleTapMarksTheRowShown].
- A Double Tap on the off-the-clock screen by accident: Undo clock-in shows for 2 minutes, while the shift has no work on it, and works while queued; it discards the workout [undoClockInIsOfferedForTwoMinutesAfterAWatchClockIn, undoClockInIsGoneAfterTwoMinutes, undoClockInGoesAwayOnceTheWatchMarksARow, undoClockInWorksWhileQueued, undoClockInCancelsTheShift, undoClockInDiscardsAtOnce, testUndoClockInGoesBackOffTheClock].
- Siri on the watch with the phone away queues and says so, unless the cached state shows it would fail [clockInWithThePhoneAwayIsSavedOnTheWatch, nextRowAwayIsSaved, clockOutAwayAsksThenSaves, statusAwayIsTheCachedAnswerAsOfItsTime, lunchAwayWhileOnLunchIsRefused].
- The Action button's clock-in names its shift for the workout before it is sent, so the workout records the Action button as its origin [anActionButtonClockInIsNamedForTheWorkoutBeforeItIsSent, aClockInFromAnyOtherDoorIsntNamed, anActionButtonClockInRecordsItsOrigin]. A session that starts after the phase change gets the next-row donation again [aWorkoutThatStartsAfterThePhaseChangeDonatesAgain].
- Health denied, never asked, or recording off: no workout, the shift goes on, the Action button still clocks in on the first press and then says "Action button needs workouts on." [deniedHealthRecordsNoWorkoutAndTheShiftGoesOn, recordingOffRecordsNoWorkout, recordingOffDonatesNothing, healthDeniedDonatesNothing, healthDeniedLaterStopsDonating, theFirstPressWithRecordingOffStillClocksIn, theFirstPressWithHealthDeniedStillClocksIn, aPressOnTheClockWithRecordingOffSaysTheButtonNeedsWorkouts, aPressOnTheClockWithHealthDeniedSaysTheButtonNeedsWorkouts].
- The field fully shaped: the button reads "Field done", and the Action button and Siri say "Every row in North is shaped." and queue nothing [noChipQueuesNothingAndSaysFieldDone, aPressWithNoRowSaysTheNoChipLine, nextRowWithTheFieldDoneQueuesNothing, nextRowOutOfKnownRowsQueuesNothing].
- Rain or sap phantom taps: the Lock (Water Lock) button shows on water-resistant watches during a session in the foreground [theRainLockShowsOnWaterResistantWatchesDuringASessionInTheForeground].
- Now never scrolls, so Double Tap always acts, also at the largest text size [testNowFitsWithoutScrolling, testNowFitsAtTheLargestText]; a wrist raise after 30 s lands on Now [aWristRaiseAfter30sLandsOnNow, aQuickGlanceAwayKeepsThePage].

### The workout
- A watch clock-out with the phone away stops the workout at the tap, keeps the session (stopped) for up to an hour, and finishes it on the answer or at 60 minutes with the reminder [queuedClockOutStopsNowFinishesOnAcknowledgementOrAfter60Minutes, aWatchClockOutStopsAtTheTapTimeBeforeAnyReply, theStuckClockOutNotifiesAfterSixtyMinutes, testAClockOutOutOfReachWaitsThenTheSummaryShows].
- A stopped session ended from outside (a clock-out waiting) finishes at its stop with its summary, keeps the reminder and offers no Record again [aStoppedSessionEndedFromOutsideFinishesAtStoppedAtKeepsTheStuckReminderAndOffersNoRecordAgain, recordAgainOffersNothingWhileTheShiftsClockOutWaits].
- A running workout ended from outside (Apple's Workout app, a crash, the battery): what was collected is saved, the shift stays on the clock and Record again starts a new one; no automatic restart after another workout [anUnexpectedEndSavesWhatWasCollectedKeepsTheShiftAndOffersRecordAgain, noAutomaticRestartAfterAnotherWorkoutEndedTheSession, aBatteryShutdownWithNoSessionToRecoverRestartsNow, recordAgainStartsANewWorkoutForTheSameShiftNow].
- The watch app killed mid-workout: recovery runs before any other input, with no second session [recoveryRunsBeforeAnyOtherInput, handleDuringRecoveryStartsNoSecondSession, aRecoveredStoppedSessionGoesStraightBackToWaitingForItsClockOut, aLostStoppedRecordThatIsLaterRecoveredStillFinishesAtItsStoppedAt].
- Two state changes during a slow start give one start [twoReconcileInputsDuringASlowStartGiveOneStart, inputsCoalesceToTheNewest].
- A phone clock-out with an untagged workout finishes it at the shift's end when that falls inside the workout, else now [untaggedSessionPlusPhoneClockOutFinishes, theFinishStaysInsideTheWorkout].
- A clock-in by mistake, then clock-out within 2 minutes: the workout is discarded and leaves no summary [aMistakenClockInThenClockOutWithinTwoMinutesStopsForTheDriverToDiscard, aWorkoutUnderTwoMinutesIsDiscardedWithNoSummary].
- A workout never starts more than 5 minutes before it was seen [aPhoneClockInSeenLateStartsNow, aWatchClockInNeverBackdatesMoreThanFiveMinutes, startTimeBackdatesAtMostFiveMinutesAndNeverIntoTheFuture].
- The shift summary reaches the phone, or waits in its slot for the next flush [theSummaryShowsForAnHourAndReachesThePhoneOrWaitsForTheNextFlush, aWorkoutSummaryGoesToThePhoneWithoutAReply, everyFlushEndsByOfferingTheWaitingSummary].
- Under half a charge at clock-in the watch says so once [aLowBatteryWarnsAtClockIn].

### Complications and the Smart Stack
- After an evening clock-out the complications read "IN" from the farm's midnight [yesterdaysHoursReadZeroTheNextMorning, offTheClockWithHoursASecondEntryAtTheFarmsMidnight, yesterdaysHoursAreGoneTheNextMorning].
- A clock-out the watch made with the phone away keeps its own day's hours [aClockOutTheWatchMadeCountsOnItsOwnDay].
- The same hours on a later day redraw [theSameHoursOnALaterDayReload].
- A Friday clock-out still raises "Clock in" on Monday [aFridayClockOutStillRaisesItOnMonday].
- Taps waiting show as "Taps waiting for iPhone" with no count, so the complication reloads only when they start or clear [tapsWaitingTakeLineThree, moreTapsWaitingDoesNotReloadUntilTheCountReachesZero, waitingTapsReloadWhenTheyStartAndWhenTheyClear].
- A stale Live Activity on the watch says "Open Time Card" [staleLineTwoAsksToOpenTimeCardLikeTheLockScreen].
- On a break the Smart Stack card keeps the worked total on line 2 ("Since 12:01 · 3:41 worked") [onLunchTheControlIsBackToWork, onABreakTheControlIsBackToWorkToo].
- VoiceOver hears the 40 mm card's whole title [theHeaderIsHeardWholeEvenWhenItsWordsDontFit].
