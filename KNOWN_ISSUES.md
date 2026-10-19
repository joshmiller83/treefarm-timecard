# Known issues

What's known to be wrong or unfinished, with the issue that tracks it. Fixed items come off this list when their issue closes.

## iPhone app

- [#1](https://github.com/joshmiller83/treefarm-timecard/issues/1) A worker promoted to admin can keep a worker's view of the farm and clear others' pay rates.
- [#2](https://github.com/joshmiller83/treefarm-timecard/issues/2) The Live Activity's first frame on the lock screen can be unreadable (seen in the simulator; check on a device).
- [#3](https://github.com/joshmiller83/treefarm-timecard/issues/3) The cold-launch Siri test doesn't run, so waking a closed app by voice is unverified.
- [#4](https://github.com/joshmiller83/treefarm-timecard/issues/4) Siri wording: some replies start a sentence in lowercase; night shifts are reported as "today".
- [#5](https://github.com/joshmiller83/treefarm-timecard/issues/5) Sync time limits can stretch past the background time an intent gets.
- [#6](https://github.com/joshmiller83/treefarm-timecard/issues/6) The database stays unsuspended after an intent-only launch (risk of iOS ending the app).
- [#7](https://github.com/joshmiller83/treefarm-timecard/issues/7) Polish: glove sizes, number styling, wording, the map's undo message, dark-mode chart contrast.

## Server and sync

- [#8](https://github.com/joshmiller83/treefarm-timecard/issues/8) Phones don't notice when the server is restored from a backup.
- [#9](https://github.com/joshmiller83/treefarm-timecard/issues/9) Small hardening: rate limits reset on restart, CLI writes can briefly clash with the running server, CI action versions.

## Landing page

- [#15](https://github.com/joshmiller83/treefarm-timecard/issues/15) **Text contrast dips during fades between story beats.** For a few dozen pixels of scroll, fading text can fall below 4.5:1. The 24-position accessibility scan reports these as "known issue #15" instead of failing; every other accessibility rule still fails the build. Also: one figure is hidden from screen readers on phones, and the "Try it" map's targets are under 44 px.
- [#14](https://github.com/joshmiller83/treefarm-timecard/issues/14) Over the performance budgets: motion JS 102 KB gz (budget 80), CSS 40 KB in total, repeated inline icons, double downloads in Safari. **CI's Lighthouse mobile performance minimum is lowered from 0.9 to 0.8** until these are fixed; raise it back when #14 closes.
- [#16](https://github.com/joshmiller83/treefarm-timecard/issues/16) Story and copy polish: counts that rest on impossible numbers, an overlap at 1024×768, a long page on phones, chapter naming, one unverified Siri line.
- [#17](https://github.com/joshmiller83/treefarm-timecard/issues/17) The timing-sensitive tests only run alone in Chromium, not in WebKit or Firefox.
- [#12](https://github.com/joshmiller83/treefarm-timecard/issues/12) The app screens are HTML recreations; real screenshots are still to come.

## Not done yet

- [#10](https://github.com/joshmiller83/treefarm-timecard/issues/10) TestFlight (needs the paid Apple Developer account). Until then, builds signed with a free Personal Team stop launching after 7 days.
- [#11](https://github.com/joshmiller83/treefarm-timecard/issues/11) Live Activity updates pushed from the server.
- [#13](https://github.com/joshmiller83/treefarm-timecard/issues/13) The Apple Watch companion (in progress).
