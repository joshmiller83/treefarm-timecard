/**
 * The crew chapter's final copy (brief: sections[crew].body and .bullets), split into a bold
 * lead and the rest so the page can set the lead in the brighter ink. crew.test.ts checks
 * every line against the brief word for word.
 */
import { CONFLICT_MESSAGE, MOMENTS, fmtClock } from '../../data/ledger.ts';

export const COPY = {
  /** Why Alex is in block 3: the ledger has Alex helping Sam finish it from 2:47. */
  lead: `At ${fmtClock(MOMENTS.crew)} you go help Sam finish block 3.`,
  // 'one map', not the brief's 'one live map': the app syncs after each change and on launch,
  // foreground, network return and background refresh, with no live push yet (truth rule 4).
  body: 'Everyone on the crew shares one map. When Sam marks a row, it shows up on your phone too.',
  offline: {
    lead: 'No signal at the back of the field? Keep working.',
    rest: 'Time Card saves your marks on your phone and syncs when you’re back in range.',
  },
  firstWins: {
    lead: 'If two people mark the same tree, the first one counts,',
    rest: 'and the other phone says so:',
    quote: CONFLICT_MESSAGE,
  },
  admins: {
    lead: 'Farm owners and crew leads are admins.',
    rest: 'They invite people with a code, set up fields and blocks, and see everyone’s hours and reports.',
  },
  workers: 'Workers see only their own hours and pay.',
  server: 'The crew shares one small server that your farm runs itself.',
} as const;

/** The five lines as single strings, in the brief's order. */
export function copyLines(): string[] {
  return [
    `${COPY.offline.lead} ${COPY.offline.rest}`,
    `${COPY.firstWins.lead} ${COPY.firstWins.rest} “${COPY.firstWins.quote}”`,
    `${COPY.admins.lead} ${COPY.admins.rest}`,
    COPY.workers,
    COPY.server,
  ];
}
