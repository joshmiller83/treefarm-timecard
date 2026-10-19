/**
 * HERO · the words: the phone's aria-label and the spoken line's word spans, from the ledger
 * and the Siri lines (never typed by hand). Build time only (Hero.astro, Said.astro); the
 * scene imports ./hero.ts instead, so none of this ships in the motion bundle.
 */
import { MOMENTS, fmtTime } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { activityView } from '../../components/system/lockscreen/activity.ts';

export const REPO = 'https://github.com/joshmiller83/treefarm-timecard';

// ---------------------------------------------------------------------------
// Words

/**
 * The phone's aria-label, as the brief words it:
 * 'iPhone lock screen at 7:02 AM. Siri says: Clocked in at 7:02. You’re on block 2, row 14.
 *  The Time Card Live Activity shows On the clock, North field, Block 2, 0 trees this shift,
 *  and buttons for row 14, row 15, row 16 and Break.'
 */
export function heroPhoneLabel(): string {
  const v = activityView({ at: MOMENTS.clockIn });
  return (
    `iPhone lock screen at ${fmtTime(MOMENTS.clockIn)}. Siri says: ${SIRI.clockIn.reply} ` +
    `The Time Card Live Activity shows ${v.pill}, ${v.field}, ${v.block}, ${v.treesText} trees this shift, ` +
    `and buttons for row ${v.rows.join(', row ')} and Break.`
  );
}

export interface SpokenWord {
  text: string;
  /** Carries the opening curly quote. */
  open: boolean;
  /** Carries the closing curly quote. */
  close: boolean;
  /** Joined to the next word with a no-break space (keeps 'Time Card' on one line). */
  glue: boolean;
}

/** A spoken line as word spans for the karaoke-style reveal. The quotes ride the end words. */
export function spokenWords(text: string): SpokenWord[] {
  const parts = text.trim().split(/\s+/);
  return parts.map((w, i) => ({
    text: w,
    open: i === 0,
    close: i === parts.length - 1,
    glue: w === 'Time' && parts[i + 1]?.startsWith('Card') === true,
  }));
}
