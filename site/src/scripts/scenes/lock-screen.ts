/**
 * SCENE STUB for 'lock-screen' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="lock-screen") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'lock-screen',
  (ctx) => {
    const { tl, day } = ctx;
    day.to(tl, MOMENTS.lockScreen, 0, 0.08, MOMENTS.status);
    day.to(tl, MOMENTS.island, 0.7, 0.85);
  },
  { dayStart: MOMENTS.status },
);
