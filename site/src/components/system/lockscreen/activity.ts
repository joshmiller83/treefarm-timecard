/**
 * LIVE ACTIVITY: what the card shows and where things sit, as pure data.
 *
 * LiveActivity.astro renders this; Vitest checks it against the ledger and the brief.
 * Geometry is in the phone's 393 × 852 pt space (brief: width 361 pt, bottom at y 760 pt,
 * radius 24 pt, padding 12/14 pt, height ≤ 160 pt, buttons 46 pt with an 8 pt gap).
 */
import {
  BREAKS,
  FIELD_TREES,
  fmtCount,
  liveActivityAt,
  MOMENTS,
  type ActivityState,
  type LiveActivityData,
  type Minute,
} from '../../../data/ledger.ts';

/** Card geometry in pt. */
export const LA = {
  left: 16,
  width: 361,
  /** y of the card's bottom edge on the 852 pt lock screen. */
  bottomY: 760,
  radius: 24,
  padX: 14,
  padY: 12,
  maxH: 160,
  /** Row heights and the space above each row, top to bottom. */
  rows: { pill: 22, timer: 34, trees: 17, buttons: 46 },
  gaps: { timer: 4, trees: 4, buttons: 8 },
  btnH: 46,
  btnR: 14,
  gap: 8,
  pillH: 22,
} as const;

export const SCREEN_H = 852;

/** Inner width: the four buttons and three gaps share it. */
export const contentWidth = LA.width - LA.padX * 2; // 333
/** One button: Row 36, Row 37, Row 38 and Break are the same width. */
export const buttonWidth = (contentWidth - LA.gap * 3) / 4; // 77.25
/** How far the strip moves to advance one row: one button plus the gap. */
export const stripStep = buttonWidth + LA.gap; // 85.25
/** The visible strip: three row buttons and two gaps. */
export const stripWidth = buttonWidth * 3 + LA.gap * 2; // 247.75
/** The card's total height (≤ 160 pt). */
export const cardHeight =
  LA.padY * 2 +
  LA.rows.pill +
  LA.gaps.timer +
  LA.rows.timer +
  LA.gaps.trees +
  LA.rows.trees +
  LA.gaps.buttons +
  LA.rows.buttons;
/** Distance from the screen's bottom edge to the card (852 − 760). */
export const bottomInset = SCREEN_H - LA.bottomY;

export interface ActivityProps {
  /** Fill everything from ledger.liveActivityAt(at). Explicit props override it. */
  at?: number;
  state?: ActivityState;
  worked?: string;
  breakTime?: string;
  breakReason?: string | null;
  trees?: number;
  field?: string;
  block?: string;
  fieldPct?: number;
  rows?: [number, number, number];
  nextRow?: number;
  undoRow?: number | null;
  fixed?: boolean;
}

export interface ActivityView {
  state: ActivityState;
  onBreak: boolean;
  tapped: boolean;
  /** The green face of the pill. */
  pillClock: string;
  /** The gold face: 'On lunch', 'On break · Sharpening shears' or 'On break'. */
  pillBreak: string;
  /** The face that shows. */
  pill: string;
  /** '{field} · {block}' */
  place: string;
  field: string;
  block: string;
  /** The big timer: the running break on break or lunch, worked time otherwise. */
  timer: string;
  worked: string;
  breakTime: string;
  trees: number;
  treesText: string;
  fieldPct: number;
  /**
   * The field bar's words, for VoiceOver only (the card shows no percent, like the app's):
   * '2,410 of 8,540 trees shaped'.
   */
  fieldLabel: string;
  rows: [number, number, number];
  nextRow: number;
  undoRow: number | null;
  /**
   * The row buttons in the strip, left to right. Working: the three rows plus the next one
   * waiting off the right edge. Tapped: the row just marked comes first and sits off the
   * left edge (the track is shifted one step left), so a scene can play the tap by moving
   * the track from x = +step to 0.
   */
  track: number[];
  /** True when the track starts one step left of the strip (tapped). */
  lead: boolean;
  /** data-timer value for the timers: 'auto' lets DayClock drive them. */
  timerMode: 'auto' | 'fixed';
  workedMode: 'worked' | 'fixed';
}

/** The next break or lunch at or after `min` (what the gold face would say if one started). */
export function nextBreakAt(min: Minute) {
  return BREAKS.find((b) => b.end > min) ?? null;
}

const defined = <T extends object>(o: T): Partial<T> =>
  Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<T>;

/** Everything LiveActivity.astro renders, from the ledger plus overrides. */
export function activityView(props: ActivityProps = {}): ActivityView {
  const at = props.at ?? MOMENTS.clockIn;
  const base: LiveActivityData = liveActivityAt(at);
  const { at: _at, fixed = false, ...overrides } = props;
  const d = { ...base, ...defined(overrides) } as LiveActivityData;

  const state = d.state;
  const onBreak = state === 'lunch' || state === 'break';
  const tapped = state === 'tapped';
  const rows = [...d.rows] as [number, number, number];
  const nextRow = props.nextRow ?? rows[2] + 1;
  const undoRow = tapped ? (props.undoRow ?? base.undoRow ?? rows[0] - 1) : null;

  // The gold face: the running break, or the one this card would show if a break began.
  let pillBreak: string;
  if (state === 'lunch') pillBreak = 'On lunch';
  else if (state === 'break') pillBreak = d.breakReason ? `On break · ${d.breakReason}` : 'On break';
  else {
    // A break from the card's Break button carries no reason (decisions.md #3).
    const next = nextBreakAt(at);
    pillBreak = next?.kind === 'lunch' ? 'On lunch' : 'On break';
  }
  const pillClock = 'On the clock';

  return {
    state,
    onBreak,
    tapped,
    pillClock,
    pillBreak,
    pill: onBreak ? pillBreak : pillClock,
    place: `${d.field} · ${d.block}`,
    field: d.field,
    block: d.block,
    timer: onBreak ? d.breakTime : d.worked,
    worked: d.worked,
    breakTime: d.breakTime,
    trees: d.trees,
    treesText: fmtCount(d.trees),
    fieldPct: d.fieldPct,
    fieldLabel: `${fmtCount(Math.round(d.fieldPct * FIELD_TREES))} of ${fmtCount(FIELD_TREES)} trees shaped`,
    rows,
    nextRow,
    undoRow,
    track: tapped && undoRow !== null ? [undoRow, ...rows, nextRow] : [...rows, nextRow],
    lead: tapped && undoRow !== null,
    timerMode: fixed ? 'fixed' : 'auto',
    workedMode: fixed ? 'fixed' : 'worked',
  };
}

/** The accessible sentence for a lock screen showing this card (for a Phone's aria-label). */
export function activityLabel(v: ActivityView): string {
  const parts = [`The Time Card Live Activity shows ${v.pill}`];
  if (v.onBreak) parts.push(`${v.timer} on ${v.state === 'lunch' ? 'lunch' : 'break'}`, `${v.worked} worked`);
  else parts.push(`${v.worked} worked`);
  parts.push(`${v.field}, ${v.block}`, `${v.treesText} trees this shift`, `a field bar: ${v.fieldLabel}`);
  if (v.tapped && v.undoRow) parts.push(`Row ${v.undoRow} marked with Undo`);
  const buttons = v.onBreak ? 'a Back to work button' : `buttons for row ${v.rows.join(', row ')} and Break`;
  return `${parts.join(', ')}, and ${buttons}.`;
}
