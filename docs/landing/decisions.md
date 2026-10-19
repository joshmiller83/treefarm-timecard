# Landing page: decisions on the brief's open questions

`brief.json` is the build spec, written by the judge of three competing concepts ("Gloves On" won). These answers settle its open questions. Where this file and the brief disagree, this file wins.

1. **Siri wording.** Use the app's real wording. These lines come from `FieldEngine` in TreeFarmKit and are covered by tests. Use the curly apostrophe (’) exactly as shown:
   - Clock in: `Clocked in at 7:02. You’re on block 2, row 14.`
   - Next row: `Row 14 marked, 10 trees. Next is row 15.` When the block changes it says `Next is block 3, row 1.`
   - Far-row check: `Row 40 in block 2? That’s 26 rows ahead.`
   - Back from lunch: `Back at 12:31. Lunch was 30 minutes.`
   - Break with a reason: `Break for sharpening shears started at 2:30.`
   - Status: `212 trees today, 34 an hour. You’re on block 2, row 35.`
   - Tree note: `Noted on block 2, row 36, tree 7.` (the brief's shorter version is wrong)
   - Shift note: `Added to today’s notes.`
   - Clock-out question: `You’ve worked 8 hours 30 minutes today. Clock out?`
   - Clock out: `Clocked out at 4:31. 8 hours 30 minutes, 290 trees.`
   - Times are spoken without AM/PM from 6:00 AM to 5:59 PM, so "7:02" and "4:31".
   - Ledger numbers are fine in every reply as long as they reconcile, and Vitest checks that.
2. **Tabs.** The app's tab bar is Clock, Trees, Log, Report, and Team for admins only. Settings is a gear button in the Clock tab's toolbar. The Log tab is real (shifts grouped by week, with editing), so it was not invented. Screens on the page may show any of these tabs.
3. **The Break button** on the Live Activity starts a break straight away, with no reason. A reason can be added later in the app, or by voice ("Take a break with Time Card"). Siri asks "What's the break for?" only when "Ask for a break reason" is on in Settings. The "Sharpening shears" beat should be the voice version.
4. **Crew marks.** On every map, trees shaped by anyone else this season (crew included) show green, "shaped earlier". Only your own current shift's trees are gold. The Live Activity's field bar counts everyone's marks.
5. **Docs.** The repo has `docs/` with architecture, api, deploy, edge-cases and voice-test, and the README shows `swift test --package-path Packages/TreeFarmKit`. Use "Read the docs" → https://github.com/joshmiller83/treefarm-timecard/tree/main/docs, and the terminal card may show that command.
6. **Beta news** will be posted in the GitHub repo (README and Releases). Use "Follow along on GitHub for news about the beta." Use no TestFlight link until one exists.
7. **Domain.** DNS is done: `treefarm.joshnliz.com` CNAME `joshmiller83.github.io` (DNS only), and the Pages custom domain is set. `timecard.joshnliz.com` is the crew server's API. Add `public/CNAME` containing `treefarm.joshnliz.com`.
8. **Versions.** Pin Astro 7.4.x and GSAP 3.15.x. The site lives in `site/` in this repo. Use Node 24 locally (`/Users/jm/Developer/gh/miller-audiobookshelf/vendor/node-v24.21.0-darwin-x64/bin`) and in CI (`actions/setup-node` with `24`).
9. **Real screenshots.** These come later from the simulator, into `site/public/screens/`. Capture first:
   - the lock screen with the Live Activity (working)
   - the Trees tab (block zoom)
   - the Report tab

   Until then, the HTML recreations are the screenshots. Every recreated screen keeps a stable `data-screen="<state-id>"` attribute so a real capture can be swapped in later.
