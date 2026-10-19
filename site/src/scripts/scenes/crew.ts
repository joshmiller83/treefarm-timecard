/**
 * SCENE STUB for 'crew' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="crew") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'crew',
  (ctx) => {
    const { tl, day } = ctx;
    day.to(tl, MOMENTS.crew, 0, 0.08, MOMENTS.backFromBreak);
    day.to(tl, MOMENTS.offline, 0.08, 0.16);
    day.to(tl, MOMENTS.samMarks, 0.16, 0.26);
    day.to(tl, MOMENTS.alexRow12, 0.26, 0.42);
    day.to(tl, MOMENTS.synced, 0.42, 0.6);
  },
  { dayStart: MOMENTS.backFromBreak },
);
