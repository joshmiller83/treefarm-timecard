/**
 * SCENE STUB for 'notes' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="notes") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'notes',
  (ctx) => {
    const { tl, day } = ctx;
    day.to(tl, MOMENTS.break, 0, 0.08, MOMENTS.island);
    day.to(tl, MOMENTS.treeNote, 0.08, 0.32);
    day.to(tl, MOMENTS.shiftNote, 0.6, 0.82);
    day.to(tl, MOMENTS.backFromBreak, 0.82, 1);
  },
  { dayStart: MOMENTS.island },
);
