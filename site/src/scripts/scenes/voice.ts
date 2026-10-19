/**
 * SCENE STUB for 'voice' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="voice") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'voice',
  (ctx) => {
    const { tl, day } = ctx;
    day.to(tl, MOMENTS.misheard, 0, 0.06, MOMENTS.clockIn);
    day.to(tl, MOMENTS.firstRow, 0.25, 0.3);
    day.to(tl, MOMENTS.lunch, 0.45, 0.5);
    day.to(tl, MOMENTS.back, 0.62, 0.7);
    day.to(tl, MOMENTS.status, 0.85, 0.9);
  },
  { dayStart: MOMENTS.clockIn },
);
