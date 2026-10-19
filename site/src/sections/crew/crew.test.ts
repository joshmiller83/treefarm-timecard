/**
 * The crew chapter's logic: the story it tells (from the ledger), the scroll schedule that
 * tells it, the second phone's geometry and the final copy (against the brief).
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { CONFLICT_MESSAGE, MOMENTS, OFFLINE, TEAM, fmtTime } from '../../data/ledger.ts';
import { COPY, copyLines } from './copy.ts';
import { POSES, poseBounds, posePoint, wirePath, type Pose } from './geometry.ts';
import { AT, DAY_FROM, DAY_TRACK, dayAt, windows } from './schedule.ts';
import { CAPTION, CONFLICT, KEPT, LABELS, OFFLINE_LINE, REJECTED, STEPS, WAITING, syncLine } from './story.ts';

const brief = JSON.parse(readFileSync(fileURLToPath(new URL('../../../../docs/landing/brief.json', import.meta.url)), 'utf8')) as {
  sections: Array<{ id: string; headline: string; body: string; bullets: string[]; eyebrow: string }>;
};
const spec = brief.sections.find((s) => s.id === 'crew')!;
/** The brief writes straight apostrophes and quotes; the page sets curly ones. */
const plain = (s: string) => s.replace(/[’‘]/g, "'").replace(/[“”]/g, '"').replace(/\s+/g, ' ').trim();

describe('the story (all from the ledger)', () => {
  it('uses the exact conflict message', () => {
    expect(CONFLICT_MESSAGE).toBe('Row 12 was shaped by Sam on Oct 16.');
  });

  it('keeps first-mark-wins: Sam marks row 12 before Alex does, offline', () => {
    expect(CONFLICT.by).toBe('Sam');
    expect(CONFLICT.row).toBe(REJECTED.row);
    expect(CONFLICT.block).toBe(REJECTED.block);
    expect(CONFLICT.at).toBeLessThan(REJECTED.at);
    expect(REJECTED.offline && REJECTED.rejected).toBe(true);
    expect(CONFLICT_MESSAGE).toContain(`Row ${CONFLICT.row}`);
    expect(CONFLICT_MESSAGE).toContain(CONFLICT.by);
  });

  it('marks rows 11 and 12 offline, keeps 11 and loses 12', () => {
    expect(KEPT.map((m) => m.row)).toEqual([11]);
    expect(REJECTED.row).toBe(12);
    expect(WAITING).toBe(2);
    expect(OFFLINE_LINE).toBe('Offline · 2 changes waiting');
    expect(syncLine(1)).toBe('Offline · 1 change waiting');
  });

  it('happens inside the offline window the ledger sets', () => {
    for (const m of [...KEPT, REJECTED]) {
      expect(m.at).toBeGreaterThanOrEqual(OFFLINE.lost);
      expect(m.at).toBeLessThan(OFFLINE.back);
    }
  });

  it('labels every phone from the ledger, with no pay, code or hostname', () => {
    expect(LABELS.main).toContain(CONFLICT_MESSAGE);
    expect(LABELS.main).toContain('Synced');
    expect(LABELS.offline).toContain(OFFLINE_LINE);
    expect(LABELS.offline).toContain('No Service');
    for (const r of TEAM) {
      expect(LABELS.owner).toContain(r.name);
      expect(LABELS.owner).toContain(r.hours);
    }
    expect(LABELS.owner).toContain('Invite someone');
    expect(LABELS.peek).toContain('Invite someone');
    for (const l of Object.values(LABELS)) {
      expect(l.length).toBeGreaterThan(40);
      expect(l).not.toMatch(/\$|joshnliz|code [A-Z0-9]{4,}|expires/i);
    }
  });

  it('captions the static figure with ledger times', () => {
    expect(STEPS.map((s) => s.time)).toEqual([fmtTime(MOMENTS.alexRow12), fmtTime(MOMENTS.synced), fmtTime(MOMENTS.synced)]);
    expect(CAPTION).toContain(CONFLICT_MESSAGE);
    expect(CAPTION).toContain(fmtTime(CONFLICT.at));
    expect(CAPTION).toContain(fmtTime(REJECTED.at));
  });
});

describe('the scroll schedule', () => {
  it('puts the copy beats where the brief says', () => {
    expect(AT.beats).toEqual([0, 0.2, 0.4, 0.66, 0.86]);
  });

  it('tweens the day forward only, from the end of the break', () => {
    expect(DAY_FROM).toBe(MOMENTS.backFromBreak);
    let t = 0;
    let min: number = DAY_FROM;
    for (const d of DAY_TRACK) {
      expect(d.start).toBeGreaterThanOrEqual(t);
      expect(d.end).toBeGreaterThan(d.start);
      expect(d.min).toBeGreaterThan(min);
      t = d.end;
      min = d.min;
    }
    expect(t).toBeLessThanOrEqual(1);
    expect(dayAt(0)).toBe(MOMENTS.backFromBreak);
    expect(dayAt(0.08)).toBe(MOMENTS.crew);
    expect(dayAt(1)).toBe(MOMENTS.synced);
  });

  it('lands every tap on its ledger minute', () => {
    expect(dayAt(AT.tap.sam)).toBe(CONFLICT.at);
    expect(dayAt(AT.tap.row11)).toBe(KEPT[0]!.at);
    expect(dayAt(AT.tap.row12)).toBe(REJECTED.at);
  });

  it('keeps first-mark-wins in the timeline: Sam taps before Alex marks row 12', () => {
    expect(AT.tap.sam).toBeLessThan(AT.tap.row11);
    expect(AT.tap.row11).toBeLessThan(AT.tap.row12);
  });

  it('loses signal at 2:48 and syncs at 3:00, as the ledger says', () => {
    expect(dayAt(AT.barsOut[0])).toBeGreaterThanOrEqual(OFFLINE.lost);
    expect(dayAt(AT.barsOut[0] - 0.02)).toBeLessThan(OFFLINE.back);
    expect(dayAt(AT.barsIn[0])).toBe(OFFLINE.back);
    expect(AT.barsIn[0]).toBeGreaterThan(AT.tap.row12);
  });

  it('turns row 12 green and shows the banner only after the sync comes back', () => {
    expect(AT.swap).toBeGreaterThanOrEqual(AT.packetDown[1]);
    expect(AT.green[0]).toBeGreaterThanOrEqual(AT.swap);
    expect(AT.banner[0]).toBeGreaterThan(AT.swap);
    expect(AT.bannerOut[0]).toBeGreaterThanOrEqual(0.6);
    expect(AT.bannerOut[1]).toBeLessThanOrEqual(0.66);
  });

  it('brings the owner forward after .66 and puts everything back by 1', () => {
    expect(AT.relabel[0]).toBeGreaterThanOrEqual(0.66);
    expect(AT.zSwap).toBeCloseTo(0.7);
    expect(AT.exit[0]).toBeGreaterThanOrEqual(0.9);
    expect(AT.exit[1]).toBeLessThanOrEqual(1);
  });

  it('places every window inside 0–1, in order', () => {
    for (const [name, w] of windows()) {
      expect(w[0], name).toBeGreaterThanOrEqual(0);
      expect(w[1], name).toBeLessThanOrEqual(1);
      expect(w[1], name).toBeGreaterThanOrEqual(w[0]);
    }
  });
});

describe('the second phone', () => {
  const box = { w: 200, h: 200 * (879 / 420) };
  const id: Pose = { x: 0, y: 0, rotate: 0, scale: 1 };

  it('maps points through a pose about the phone’s centre', () => {
    const same = posePoint(box, id, 0.25, 0.5);
    expect(same.x).toBeCloseTo(50);
    expect(same.y).toBeCloseTo(box.h / 2, 2);
    const moved = posePoint(box, { ...id, x: 0.3 }, 0, 0);
    expect(moved.x).toBeCloseTo(60);
    const half = posePoint(box, { ...id, scale: 0.5 }, 0, 0);
    expect(half.x).toBeCloseTo(50);
    expect(half.y).toBeCloseTo(box.h / 4);
    const turned = posePoint({ w: 100, h: 100 }, { ...id, rotate: 90 }, 1, 0.5);
    expect(turned.x).toBeCloseTo(50);
    expect(turned.y).toBeCloseTo(100);
  });

  it('peeks out on the side its row numbers are on, smaller and tilted, then comes forward', () => {
    for (const k of ['desk', 'mob'] as const) {
      const p = POSES[k];
      expect(p.rest.x).toBeLessThan(0);
      expect(p.rest.scale).toBeLessThan(1);
      expect(p.front.scale).toBe(1);
      expect(Math.abs(p.front.x)).toBeLessThan(Math.abs(p.rest.x));
      expect(p.hidden.x).toBe(0);
    }
  });

  it('never pushes past a 16px gutter at 320 and 375 wide', () => {
    for (const [vw, vh] of [
      [320, 640],
      [375, 667],
      [375, 812],
    ] as const) {
      const h = Math.min(0.46 * vh, 400);
      const w = (h * 420) / 879;
      const left = (vw - w) / 2;
      for (const pose of [POSES.mob.rest, POSES.mob.front]) {
        const b = poseBounds({ w, h }, pose);
        expect(left + b.left, `${vw}×${vh}`).toBeGreaterThanOrEqual(16);
        expect(left + b.right, `${vw}×${vh}`).toBeLessThanOrEqual(vw - 16);
      }
    }
  });

  it('draws a wire from one point to the other', () => {
    const d = wirePath({ x: 10, y: 80 }, { x: 120, y: -20 });
    expect(d.startsWith('M10 80')).toBe(true);
    expect(d.endsWith('120 -20')).toBe(true);
  });
});

describe('the copy', () => {
  it('is the brief’s headline, body and five lines, word for word', () => {
    expect(plain(COPY.body)).toBe(plain(spec.body));
    expect(copyLines().map(plain)).toEqual(spec.bullets.map(plain));
  });

  it('quotes the conflict message exactly', () => {
    expect(COPY.firstWins.quote).toBe(CONFLICT_MESSAGE);
  });

  it('uses curly apostrophes on the page', () => {
    expect(copyLines().join(' ')).not.toContain("'");
  });
});
