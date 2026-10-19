/**
 * SCENE STUB for 'open' (the section team owns this file). Spec:
 *   jq '.sections[] | select(.id=="open") | .animation' docs/landing/brief.json
 * ctx.tl is scrubbed and normalized to 0–1. Leave ctx.phone at rest at 0 and 1.
 * The day tweens below keep the DayClock, status bars, ribbon and DayMark moving
 * through the story until the real scene lands.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';

registerScene(
  'open',
  (ctx) => {
    const { tl, day } = ctx;
    // The shift is over: hold 4:31 PM with the ribbon complete ('End of shift').
    // The open section's own motion is triggered on enter (ctx.trigger), not scrubbed.
    day.to(tl, MOMENTS.clockOut, 0, 0.01, MOMENTS.clockOut);
    day.complete(tl, 0, 0.01);
  },
  { dayStart: MOMENTS.clockOut },
);
