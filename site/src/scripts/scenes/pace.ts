/**
 * SCENE STUB for 'pace' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="pace") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'pace',
  (ctx) => {
    const { tl, day } = ctx;
    day.to(tl, MOMENTS.pace, 0, 0.1, MOMENTS.synced);
  },
  { dayStart: MOMENTS.synced },
);
