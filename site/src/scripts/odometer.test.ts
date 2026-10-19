import { describe, expect, it } from 'vitest';
import { digitsOf, odometerHTML, odometerShape, setOdometer, setOdometerInstant } from './odometer.ts';

function fakeEl(text?: string) {
  const cols: Array<{ style: { transform: string; transition?: string } }> = [];
  const el = {
    dataset: {} as Record<string, string>,
    _html: '',
    get innerHTML() {
      return this._html;
    },
    set innerHTML(v: string) {
      this._html = v;
      cols.length = 0;
      for (const m of v.matchAll(/translateY\((-?\d+)%\)/g)) cols.push({ style: { transform: `translateY(${m[1]}%)` } });
    },
    querySelectorAll: () => cols,
  };
  if (text !== undefined) {
    el.innerHTML = odometerHTML(text);
    el.dataset.odoText = text;
  }
  return { el, cols };
}

describe('odometer digits', () => {
  it('renders one 0–9 column per digit, positioned at the digit', () => {
    const html = odometerHTML('6:27:00');
    expect(html.match(/class="odo-col"/g)).toHaveLength(5);
    expect(html).toContain('translateY(-60%)');
    expect(html.match(/class="odo-s">:</g)).toHaveLength(2);
  });

  it('knows when two readings share a shape', () => {
    expect(odometerShape('6:27:00')).toBe(odometerShape('7:39:00'));
    expect(odometerShape('9:59:59')).not.toBe(odometerShape('10:00:00'));
    expect(digitsOf('1:46')).toEqual([1, 4, 6]);
  });

  it('moves columns in place when the shape matches', () => {
    const { el, cols } = fakeEl('6:27:00');
    setOdometer(el, '6:29:10');
    expect(cols.map((c) => c.style.transform)).toEqual([
      'translateY(-60%)',
      'translateY(-20%)',
      'translateY(-90%)',
      'translateY(-10%)',
      'translateY(0%)',
    ]);
  });

  it('rebuilds when the number of digits changes', () => {
    const { el, cols } = fakeEl('9:59:59');
    setOdometer(el, '10:00:00');
    expect(cols).toHaveLength(6);
    expect(el.dataset.odoText).toBe('10:00:00');
  });

  it('jumps (no transition) on the columns it moves while the page scrolls, and rolls again after', () => {
    const { el, cols } = fakeEl('6:27:00');
    setOdometerInstant(true);
    setOdometer(el, '6:27:01');
    expect(cols[4]!.style.transition).toBe('none');
    expect(cols[0]!.style.transition).toBeUndefined();
    setOdometerInstant(false);
    setOdometer(el, '6:27:02');
    expect(cols[4]!.style.transition).toBe('');
  });
});
