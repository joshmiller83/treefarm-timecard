/**
 * Odometer digits: each digit is a clipped column of 0–9 moved by translateY, so numbers
 * roll instead of jumping and only transforms change. Server markup comes from
 * odometerHTML() (final value, correct without JS); DayClock and util.odometer() update
 * it with setOdometer(). Styles live in global.css (.odo, .odo-d, .odo-col).
 *
 * Pure string building, no DOM at import time: safe in Astro frontmatter and in Vitest.
 */

const DIGITS = '0123456789';
const isDigit = (ch: string) => ch >= '0' && ch <= '9';

/** The column's ten digits, one per line, as a single text node (white-space: pre in CSS):
 * one element per digit instead of eleven keeps the page's DOM small. */
const COLUMN = Array.from(DIGITS).join('\n');

const col = (d: number) => `<span class="odo-d"><span class="odo-col" style="transform:translateY(${-d * 10}%)">${COLUMN}</span></span>`;

const escape = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);

/** Markup for an odometer reading `text` (digits roll; everything else is static). */
export function odometerHTML(text: string): string {
  let out = '';
  for (const ch of text) out += isDigit(ch) ? col(Number(ch)) : `<span class="odo-s">${escape(ch)}</span>`;
  return out;
}

/** The shape of a reading: digits become 'd', so '6:27:00' and '7:39:00' match. */
export const odometerShape = (text: string) => Array.from(text, (ch) => (isDigit(ch) ? 'd' : ch)).join('');

interface OdoHost {
  dataset: DOMStringMap;
  innerHTML: string;
  querySelectorAll(sel: string): ArrayLike<{ style: { transform: string; transition?: string } }>;
}

/**
 * While the reader scrolls, digits jump instead of rolling (the scroll position drives them
 * already). The motion core flips this on scrollStart/scrollEnd; each column that moves
 * carries it inline, so no class on a chapter or <html> restyles the page around it.
 */
let instant = false;
export function setOdometerInstant(on: boolean): void {
  instant = on;
}

/** Update an element rendered with odometerHTML (rebuilds only when the shape changes). */
export function setOdometer(el: OdoHost, text: string): void {
  if (el.dataset.odoText === text) return;
  const prev = el.dataset.odoText;
  el.dataset.odoText = text;
  const cols = el.querySelectorAll('.odo-col');
  if (prev === undefined || odometerShape(prev) !== odometerShape(text) || cols.length !== digitsOf(text).length) {
    el.innerHTML = odometerHTML(text);
    return;
  }
  const transition = instant ? 'none' : '';
  digitsOf(text).forEach((d, i) => {
    const c = cols[i];
    if (!c) return;
    const transform = `translateY(${-d * 10}%)`;
    if (c.style.transform === transform) return;
    if ((c.style.transition ?? '') !== transition) c.style.transition = transition;
    c.style.transform = transform;
  });
}

/** Digits of `text`, used by tests and by util.odometer() to tween columns. */
export const digitsOf = (text: string) => Array.from(text).filter(isDigit).map(Number);
