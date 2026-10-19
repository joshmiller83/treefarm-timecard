/**
 * SCENE STUB for 'hero' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="hero") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'hero',
  (ctx) => {
    const { tl, day } = ctx;
    // The hero holds at 7:02. The on-load sequence (not scroll-linked) goes here.
    day.to(tl, MOMENTS.clockIn, 0, 1, MOMENTS.clockIn);
  },
  { dayStart: MOMENTS.clockIn },
);
