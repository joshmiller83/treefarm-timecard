/**
 * SCENE STUB for 'field' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="field") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'field',
  (ctx) => {
    const { tl, day } = ctx;
    // The field holds where the lock-screen beat ended (2:16 PM); notes picks up from there.
    day.to(tl, MOMENTS.island, 0, 0.02, MOMENTS.island);
  },
  { dayStart: MOMENTS.island },
);
