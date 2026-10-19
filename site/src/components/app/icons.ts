/**
 * Original inline SVG glyphs in an SF-Symbols-like style (24 × 24, rounded 1.75 strokes).
 * They are drawn for this site; Apple's symbols are never copied or shipped.
 *
 * IconSprite.astro renders them once as <symbol id="i-{name}">; Icon.astro references them
 * with <use>, so repeated glyphs cost a few bytes each.
 */

export interface Glyph {
  /** Inner SVG markup in a 24 × 24 box. */
  body: string;
  /** Filled glyph (fill: currentColor) instead of a stroked one. */
  fill?: boolean;
}

const S = (body: string): Glyph => ({ body });
const F = (body: string): Glyph => ({ body, fill: true });

// A fir with three rounded tiers, like the app icon's tree.
const FIR_OUTLINE = 'M12 2.8 7.6 8.6h2.3L6.2 13.5h2.6L5.1 18.6h13.8l-3.7-5.1h2.6l-3.7-4.9h2.3Z';

export const GLYPHS = {
  // Tab bar (decisions.md #2: Clock, Trees, Log, Report, Team)
  clock: S('<circle cx="12" cy="12" r="9"/><path d="M12 7v5.2l3.4 2"/>'),
  'clock.fill': F(
    '<path fill-rule="evenodd" d="M12 2.6a9.4 9.4 0 1 1 0 18.8 9.4 9.4 0 0 1 0-18.8Zm.9 4.4a.9.9 0 0 0-1.8 0v5.2c0 .3.2.6.4.8l3.4 2a.9.9 0 1 0 .9-1.6l-2.9-1.7Z"/>',
  ),
  tree: S(`<path d="${FIR_OUTLINE}"/><path d="M12 18.6v2.8"/>`),
  'tree.fill': F(`<path d="${FIR_OUTLINE}" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><rect x="10.9" y="17.5" width="2.2" height="4.4" rx="1"/>`),
  list: S('<path d="M9.5 6.5h10.5M9.5 12h10.5M9.5 17.5h10.5"/><circle cx="4.9" cy="6.5" r=".6"/><circle cx="4.9" cy="12" r=".6"/><circle cx="4.9" cy="17.5" r=".6"/>'),
  'list.fill': F(
    '<path fill-rule="evenodd" d="M6.5 3h11A3.5 3.5 0 0 1 21 6.5v11a3.5 3.5 0 0 1-3.5 3.5h-11A3.5 3.5 0 0 1 3 17.5v-11A3.5 3.5 0 0 1 6.5 3Zm1.4 4.2a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Zm3.3.3a.8.8 0 0 0 0 1.6h5.6a.8.8 0 0 0 0-1.6Zm-3.3 3.4a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Zm3.3.3a.8.8 0 0 0 0 1.6h5.6a.8.8 0 0 0 0-1.6Zm-3.3 3.4a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Zm3.3.3a.8.8 0 0 0 0 1.6h5.6a.8.8 0 0 0 0-1.6Z"/>',
  ),
  doc: S('<path d="M7 2.8h6.6L19 8.2v10.6a2.4 2.4 0 0 1-2.4 2.4H7a2.4 2.4 0 0 1-2.4-2.4V5.2A2.4 2.4 0 0 1 7 2.8Z"/><path d="M13.4 3v5.3H19M8.6 13h6.8M8.6 16.6h4.6"/>'),
  'doc.fill': F(
    '<path fill-rule="evenodd" d="M7 2.4h5.8v5.1c0 .9.7 1.6 1.6 1.6h5v9.7a2.8 2.8 0 0 1-2.8 2.8H7a2.8 2.8 0 0 1-2.8-2.8V5.2A2.8 2.8 0 0 1 7 2.4Zm1.6 9.8a.8.8 0 0 0 0 1.6h6.8a.8.8 0 0 0 0-1.6Zm0 3.6a.8.8 0 0 0 0 1.6h4.6a.8.8 0 0 0 0-1.6Z"/><path d="M14.4 2.6 19.2 7.5h-4.3a.5.5 0 0 1-.5-.5Z"/>',
  ),
  people: S('<circle cx="9" cy="8.2" r="3.3"/><path d="M3.2 19.6c.6-3.4 2.9-5.3 5.8-5.3s5.2 1.9 5.8 5.3"/><path d="M15.4 5.3a3 3 0 0 1 0 5.8M17.6 14.6c1.8.6 3 2.2 3.4 4.6"/>'),
  'people.fill': F(
    '<circle cx="9" cy="8.2" r="3.7"/><path d="M2.7 19.4c.6-3.8 3.2-6 6.3-6s5.7 2.2 6.3 6c.1.7-.4 1.2-1 1.2H3.7c-.6 0-1.1-.5-1-1.2Z"/><path d="M15.1 4.6a3.7 3.7 0 0 1 0 7.2 5 5 0 0 0 0-7.2ZM16.9 13.7c2.4.7 4 2.7 4.4 5.7.1.7-.4 1.2-1 1.2h-2.5c.1-.4.1-.8 0-1.3-.3-2.3-1.2-4.2-2.6-5.4.6-.2 1.1-.2 1.7-.2Z"/>',
  ),

  // Toolbar and controls
  gear: S('<circle cx="12" cy="12" r="8.1" stroke-width="2.7" stroke-dasharray="2.55 3.81" stroke-linecap="butt"/><circle cx="12" cy="12" r="6.1"/><circle cx="12" cy="12" r="2.5"/>'),
  mic: S('<rect x="9" y="2.8" width="6" height="11.4" rx="3"/><path d="M5.6 11.2a6.4 6.4 0 0 0 12.8 0M12 17.6v3.4M8.8 21h6.4"/>'),
  pause: F('<rect x="6.2" y="4.8" width="4" height="14.4" rx="1.3"/><rect x="13.8" y="4.8" width="4" height="14.4" rx="1.3"/>'),
  play: F('<path d="M8.2 4.9c0-.9 1-1.5 1.8-1l9 6.2c.7.5.7 1.5 0 2l-9 6.2c-.8.5-1.8 0-1.8-1Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/>'),
  undo: S('<path d="M8.6 13.9 4.4 9.7l4.2-4.2"/><path d="M4.6 9.7h9.9a5.4 5.4 0 0 1 0 10.8h-3.2"/>'),
  flag: S('<path d="M5.6 21.2V3.6"/><path d="M5.6 4.4h11.8l-2.6 4.3 2.6 4.3H5.6"/>'),
  'flag.fill': F('<path d="M5.6 2.8c.5 0 .9.4.9.9v.1h10.9c.7 0 1.1.7.8 1.3l-2.4 3.9 2.4 3.9c.4.6 0 1.3-.8 1.3H6.5v7c0 .5-.4.9-.9.9s-.9-.4-.9-.9V3.7c0-.5.4-.9.9-.9Z"/>'),
  note: S('<rect x="4" y="3.2" width="16" height="17.6" rx="3"/><path d="M8 8.4h8M8 12h8M8 15.6h4.6"/>'),
  pencil: S('<path d="M4.2 19.8 5 15.9 15.6 5.3a2 2 0 0 1 2.9 0l.2.2a2 2 0 0 1 0 2.9L8.1 19Z"/><path d="m13.9 7 3.1 3.1"/>'),
  wifi: S('<path d="M2.6 9.2a13.4 13.4 0 0 1 18.8 0M5.9 12.6a8.6 8.6 0 0 1 12.2 0M9.2 16a3.9 3.9 0 0 1 5.6 0"/><circle cx="12" cy="19.3" r="1.2" fill="currentColor" stroke="none"/>'),
  'wifi.slash': S('<path d="M2.6 9.2a13.4 13.4 0 0 1 4.6-3M10.4 4.9a13.4 13.4 0 0 1 11 4.3M5.9 12.6a8.6 8.6 0 0 1 4-2.2M15 10.7c1.1.4 2.2 1.1 3.1 1.9M9.2 16a3.9 3.9 0 0 1 5.6 0M3.5 3.2l17 17.6"/><circle cx="12" cy="19.3" r="1.2" fill="currentColor" stroke="none"/>'),
  check: S('<path d="m5 12.6 4.4 4.4L19.2 7"/>'),
  'check.circle': F('<path fill-rule="evenodd" d="M12 2.6a9.4 9.4 0 1 1 0 18.8 9.4 9.4 0 0 1 0-18.8Zm4.5 6.2a.9.9 0 0 0-1.3 0l-4.4 4.6-2-2a.9.9 0 1 0-1.3 1.2l2.7 2.7c.4.4.9.4 1.3 0l5-5.2a.9.9 0 0 0 0-1.3Z"/>'),
  chevron: S('<path d="m9.4 5.4 6.6 6.6-6.6 6.6"/>'),
  'chevron.down': S('<path d="m5.6 9.2 6.4 6.4 6.4-6.4"/>'),
  'chevron.left': S('<path d="M14.6 5.4 8 12l6.6 6.6"/>'),
  'chevron.up.down': S('<path d="m8 9.4 4-4 4 4M8 14.6l4 4 4-4"/>'),
  share: S('<path d="M12 14.4V3.4M8 7.2l4-3.8 4 3.8"/><path d="M8.2 10.2H7a2 2 0 0 0-2 2v6.6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6.6a2 2 0 0 0-2-2h-1.2"/>'),
  eye: S('<path d="M2.4 12s3.6-6.6 9.6-6.6 9.6 6.6 9.6 6.6-3.6 6.6-9.6 6.6S2.4 12 2.4 12Z"/><circle cx="12" cy="12" r="3"/>'),
  'eye.slash': S('<path d="M9.6 5.7c.8-.2 1.5-.3 2.4-.3 6 0 9.6 6.6 9.6 6.6s-.9 1.7-2.6 3.3M16.4 17.2c-1.3.8-2.8 1.4-4.4 1.4-6 0-9.6-6.6-9.6-6.6s1.2-2.2 3.4-4.1M9.9 9.9a3 3 0 0 0 4.2 4.2M3.6 3.4l16.8 17.2"/>'),
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  xmark: S('<path d="m6.4 6.4 11.2 11.2M17.6 6.4 6.4 17.6"/>'),
  'person.add': S('<circle cx="9.5" cy="8.2" r="3.4"/><path d="M3.4 19.6c.6-3.4 3-5.3 6.1-5.3 1.7 0 3.1.5 4.2 1.5M18.2 13.2v6.4M15 16.4h6.4"/>'),
  grid: S('<rect x="3.6" y="3.6" width="7" height="7" rx="1.8"/><rect x="13.4" y="3.6" width="7" height="7" rx="1.8"/><rect x="3.6" y="13.4" width="7" height="7" rx="1.8"/><rect x="13.4" y="13.4" width="7" height="7" rx="1.8"/>'),
  calendar: S('<rect x="3.6" y="4.8" width="16.8" height="15.6" rx="3"/><path d="M3.6 9.6h16.8M8 3v3.4M16 3v3.4"/>'),
  mappin: S('<path d="M12 21.2s-6.6-6-6.6-11.2a6.6 6.6 0 0 1 13.2 0c0 5.2-6.6 11.2-6.6 11.2Z"/><circle cx="12" cy="10" r="2.4"/>'),
  house: S('<path d="M4 10.4 12 3.8l8 6.6V19a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z"/><path d="M9.6 21v-5.4h4.8V21"/>'),
  lock: F('<path fill-rule="evenodd" d="M12 2.8a4.6 4.6 0 0 1 4.6 4.6v2.4h.4a2.2 2.2 0 0 1 2.2 2.2v7.2a2.2 2.2 0 0 1-2.2 2.2H7a2.2 2.2 0 0 1-2.2-2.2V12A2.2 2.2 0 0 1 7 9.8h.4V7.4A4.6 4.6 0 0 1 12 2.8Zm0 1.8a2.8 2.8 0 0 0-2.8 2.8v2.4h5.6V7.4A2.8 2.8 0 0 0 12 4.6Z"/>'),
  flashlight: S('<path d="M8 2.8h8v4.4l-2 3.4v9.2a1.6 1.6 0 0 1-1.6 1.6h-.8a1.6 1.6 0 0 1-1.6-1.6v-9.2l-2-3.4Z"/><path d="M8 7.2h8M12 13.4v2"/>'),
  camera: S('<path d="M4.6 7.4h3l1.6-2.4h5.6l1.6 2.4h3a1.8 1.8 0 0 1 1.8 1.8v8.6a1.8 1.8 0 0 1-1.8 1.8H4.6a1.8 1.8 0 0 1-1.8-1.8V9.2a1.8 1.8 0 0 1 1.8-1.8Z"/><circle cx="12" cy="13.2" r="3.4"/>'),
  waveform: S('<path d="M4 10.2v3.6M8 7v10M12 3.8v16.4M16 7.8v8.4M20 10.4v3.2"/>'),
  earbuds: S('<path d="M8.4 3.6a3.4 3.4 0 0 0-3.4 3.4v.4a3.4 3.4 0 0 0 2.8 3.3v8.1a1.4 1.4 0 0 0 2.8 0V7.6a4 4 0 0 0-2.2-4Z"/><path d="M15.6 3.6a3.4 3.4 0 0 1 3.4 3.4v.4a3.4 3.4 0 0 1-2.8 3.3v8.1a1.4 1.4 0 0 1-2.8 0V7.6a4 4 0 0 1 2.2-4Z"/>'),
  bell: S('<path d="M6.2 16.6V11a5.8 5.8 0 0 1 11.6 0v5.6l1.6 1.8H4.6Z"/><path d="M10 20.4a2.1 2.1 0 0 0 4 0"/>'),
  scissors: S('<circle cx="6.4" cy="17.4" r="2.8"/><circle cx="17.6" cy="17.4" r="2.8"/><path d="M8.4 15.4 18.4 3.6M15.6 15.4 5.6 3.6"/>'),
  drop: S('<path d="M12 3.2s6 6.4 6 11a6 6 0 0 1-12 0c0-4.6 6-11 6-11Z"/>'),
  'fork.knife': S('<path d="M7 3v6.4a2.2 2.2 0 0 0 4.4 0V3M9.2 3v18M16.8 21V3c-1.9 1-3 3.2-3 6v4.8h3"/>'),
  ellipsis: F('<circle cx="5.6" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="18.4" cy="12" r="1.7"/>'),
  'hand.tap': S('<path d="M9.6 12.6V5.8a1.6 1.6 0 0 1 3.2 0v5.4l4.6.9c1.1.2 1.8 1.2 1.6 2.3l-.9 4.4a2.6 2.6 0 0 1-2.5 2.1h-4.4a2.6 2.6 0 0 1-2-1l-3-3.9a1.5 1.5 0 0 1 2.2-2Z"/><path d="M6.6 6.2a4.8 4.8 0 0 1 9.2-.8"/>'),
  'arrow.down': S('<path d="M12 4.4v15.2M6 13.6l6 6 6-6"/>'),
  'arrow.up.right': S('<path d="M7 17 17 7M8.6 7H17v8.4"/>'),
  server: S('<rect x="3.6" y="4" width="16.8" height="7" rx="2"/><rect x="3.6" y="13" width="16.8" height="7" rx="2"/><path d="M7.4 7.5h.01M7.4 16.5h.01"/>'),
  leaf: F(`<path d="${FIR_OUTLINE}"/><rect x="10.9" y="17.5" width="2.2" height="4.4" rx="1"/>`),
} satisfies Record<string, Glyph>;

export type IconName = keyof typeof GLYPHS;
export const ICON_NAMES = Object.keys(GLYPHS) as IconName[];
