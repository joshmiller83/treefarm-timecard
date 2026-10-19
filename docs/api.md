# HTTP API

Base URL in production: `https://timecard.joshnliz.com`. Every body is JSON written with `JSONCoding` from TreeFarmKit (dates are milliseconds since 1970). The Swift types for every body live in `Packages/TreeFarmKit/Sources/TreeFarmKit/Sync/API.swift` and `SyncProtocol.swift`, so the app and server can't drift. The server always writes whole milliseconds, so a record that goes out and comes back encodes to the same bytes.

Authenticated routes take `Authorization: Bearer <token>`. Errors answer with an HTTP status and `APIErrorBody { error: true, reason }`, where `reason` is a sentence fit to show a person. Statuses: 400 (bad body or query), 401 (no valid session: sign in again), 403, 404, 409 (conflicts with the account or farm as it stands), 413 (body over 2 MB, or more than `Limits.pushBatch` mutations), 429 (rate limited; has `Retry-After` in seconds), 500 (never carries details).

`GET /` redirects (302) to `https://treefarm.joshnliz.com`, so someone who types the API host into a browser lands somewhere friendly.

## Accounts

| Method | Path | Body → Answer | Notes |
|---|---|---|---|
| GET | `/health` | → `HealthResponse` | No auth. |
| POST | `/v1/auth/login` | `LoginRequest` → `AuthResponse` | Rate limited (below). 401 for a wrong email or password (same sentence for both). 403 when the person is no longer on any farm. |
| POST | `/v1/auth/register` | `RegisterRequest` → `AuthResponse` | Needs a live invite code (single use, 7 days); 400 says whether it's wrong, used or expired. Invite-only: there is no open signup. Passwords are 8 to 200 characters. If the email already has an account, the right password joins (or rejoins) the invite's farm with that account; a wrong one is 409, and so is someone already on the farm. |
| POST | `/v1/auth/reset` | `ResetPasswordRequest` → `AuthResponse` | Reset code from an admin (single use, 24 hours). Sets the password, signs out every existing session and starts a new one. |
| POST | `/v1/auth/logout` | → 204 | Revokes the calling session. |
| GET | `/v1/me` | → `MeResponse` | The user, their current farms and their own memberships (never redacted). |
| PATCH | `/v1/me` | `UpdateMeRequest` → `MeResponse` | A new `displayName` reaches the person's membership on every farm. Changing the password needs `currentPassword` (400 if missing, 403 if wrong) and signs out every other session. |
| DELETE | `/v1/me` | `DeleteAccountRequest` → 204 | 403 for a wrong password. Deletes the login and its sessions. Shifts stay with the farm: each membership gets `removedAt` and keeps the name, but the email is blanked. 409 if the person is the only admin of a farm that has other people. |
| GET | `/v1/me/sessions` | → `[SessionInfo]` | Live sessions, most recently used first. |
| DELETE | `/v1/me/sessions/:id` | → 204 | 404 if it isn't one of the caller's live sessions. |

Sessions are opaque 32-byte tokens; the server keeps only their SHA-256. They expire after 90 days without use (each use slides the expiry).

**Rate limits.** Login, register and reset share a limit of 20 attempts per client address per 15 minutes. Five wrong passwords or reset codes for one email lock it for 15 minutes, even for the right password. Both answer 429 with `Retry-After`. Behind the Cloudflare Tunnel the client address is `CF-Connecting-IP`, believed only when the connection comes from localhost (cloudflared). Limits live in memory, so a restart clears them.

## Farm data (sync)

All farm routes check that the caller is a current member of `:farmId`: anyone else, including someone removed from the farm, gets 403.

| Method | Path | Body → Answer | Notes |
|---|---|---|---|
| POST | `/v1/farms/:farmId/sync/push` | `PushRequest` → `PushResponse` | Up to `Limits.pushBatch` mutations (413 above that). One result per mutation, in order; each runs in its own transaction. Retrying a mutation id returns its first result without applying it again; an id someone else already used is `forbidden`. |
| GET | `/v1/farms/:farmId/sync/pull?since=<seq>&limit=<n>` | → `PullResponse` | Changes after `since` (default 0) that the caller may see, oldest first, `limit` default 500, at most 1000. `cursor` is the last seq returned, or `since` when nothing is. Keep pulling while `hasMore`. |
| GET | `/v1/farms/:farmId/export.csv?from=<ms>&to=<ms>&userId=<id>` | → CSV | See below. |

Seqs are server-wide and assigned in commit order (the server runs every transaction on one SQLite connection), so pulling from the last cursor never skips a change.

### Who can push what

| Record | Worker | Admin |
|---|---|---|
| `shift` | Own shifts only. | Anyone's on the farm. A shift can't move to another person. |
| `treeMark` | Marks on their own shifts. | Any. |
| `treeNote` | Create any (in their own name); edit or delete their own. | Any. |
| `field`, `block`, `season` | No. | Yes. |
| `farm` | No. | Yes (name, time zone, week start, active season). Only the farm in the path; farms aren't created by push. |
| `member` | Their own `displayName`, `jobTitle`, `rateCents`. | Anyone's name, job, rate, role and `removedAt` (an admin can undo a removal). The farm always keeps one current admin. |

A record's farm must be the farm in the path (`forbidden` otherwise), and anything it points at (field, block, season, shift, person) must be on that farm (`notFound` otherwise). Members can't be created by push: people join with invites. `email` on a member always comes from the account.

### Who can pull what

Everyone on a farm pulls the farm, seasons, fields, blocks, every tree mark and every tree note, since the map is shared. Shifts: workers pull their own, admins pull everyone's. Members: workers see names and roles; other people's email and rate come back blank (`""` and `0`). Visibility follows the caller's role at pull time, so a worker made admin should pull again from 0 to get everyone's shifts.

### What the server checks

- **Shifts** go through `ShiftRules.normalized` (breaks sorted, notes and reasons trimmed to `Limits`) and then `ShiftRules.validate` against the person's other shifts, with `Limits.clockSkew` (5 minutes) of tolerance for future times. The rate can't be negative. Deleting a shift also deletes its tree marks (they get new seqs), so its trees are free again.
- **Tree marks** must be on the farm's active season, inside a live block, on a live shift, and carry that shift's person as `userId`. A mark can't move to another tree. Deleting one frees the tree.
- **Blocks** follow `BlockEdit.validate` (name, 1–300 rows, 1–300 trees a row) and sit at grid row and column 0–999. Moving around the grid is always fine.
- **Fields** need a name; a field with live blocks can't be deleted (archiving is fine).
- **Notes**: the server sets `authorName` from the writer's membership and keeps `authorId`, `authorName` and `createdAt` as first stored. Bodies are trimmed to `Limits.notes`. A note can't move to another tree.
- **Members**: names up to `Limits.name`, rates from 0 to $10,000 an hour. Someone whose account is deleted can't be restored (send a new invite). A removal that takes someone off their last farm signs them out everywhere.
- **Farm**: a real IANA time zone, and the active season must be one of the farm's.

### Rejections

A rejected mutation carries a `RejectReason` and a `message` the app shows or speaks as-is. Whenever the server has a copy of the record that the caller may see, `current` is that copy (redacted as a pull would be), so the device can replace its own without pulling everything again.

- `treeTaken`: another live mark holds this tree this season. First write wins. `current` is the winning mark, and the message reads "Row 12, tree 4 in Block 2 was shaped by Sam on Oct 16." (block names as `Block.displayName`, the day in the farm's time zone, "you" when it was the caller).
- `openShiftExists`: the person already has an open shift on this farm. `current` is that shift. "You’re already clocked in (since Fri, Oct 16 at 7:02 AM)."
- `blockInUse`: a resize, a move to another field or a removal would strand live marks (from any season) or notes. The message comes from `BlockEdit`.
- `invalid`: a ShiftRules, size or name rule failed, or the push was a stale copy (below); `message` says which.
- `forbidden`, `notFound`.

### Conflict rules

- The same for every kind of record: if the server's copy is identical, or both copies are deleted, the push is `applied` with the stored seq and nothing changes. Otherwise the newer `updatedAt` (to the millisecond) wins; an older copy, or a different copy with the same `updatedAt` (ties go to the copy the server already has), is refused as `invalid`, "A newer copy of this shift is on the server.", with the server's copy in `current`.
- Tree marks: on top of that, first commit wins for a tree in a season, whatever the timestamps.
- Everything is soft-deleted with `deletedAt` (members with `removedAt`), so a delete is just another upsert. A stale live copy can't bring back something deleted later.

### CSV export

Columns: `Name, Date, In, Out, Breaks, Hours, Notes`. One row per live shift that clocks in within [`from`, `to`) (both optional, milliseconds), oldest first. `Date` is `yyyy-MM-dd` and `In`/`Out` are like `7:02 AM`, in the farm's time zone. `Breaks` is whole minutes and isn't counted in `Hours`, which has two decimals (`Fmt.decimalHours`). An open shift has an empty `Out` and its hours so far. Quoting follows RFC 4180 with CRLF line ends, and a field that starts with `=`, `+`, `-` or `@` gets a leading `'` so spreadsheets don't run it. Workers get their own shifts only (403 for another `userId`); admins may pass any `userId` or leave it out for everyone.

## Admin

| Method | Path | Body → Answer |
|---|---|---|
| GET | `/v1/farms/:farmId/invites` | → `[InviteInfo]`, newest first, including used ones (no codes) |
| POST | `/v1/farms/:farmId/invites` | `CreateInviteRequest` → `InviteInfo` with `code` (single use, 7 days; the note is trimmed to 80 characters) |
| DELETE | `/v1/farms/:farmId/invites/:id` | → 204, or 404 if it isn't this farm's |
| POST | `/v1/farms/:farmId/members/:userId/reset` | → `ResetCodeResponse` (single use, 24 hours; replaces the person's earlier unused code). 404 unless they're a current member. |
| DELETE | `/v1/farms/:farmId/members/:userId` | → 204 (sets `removedAt` through the same path as a pushed member change, so it syncs; hours stay). 204 again if already removed, 404 for someone not on the farm, 409 for the last admin. |

Codes are 10 characters from an alphabet without 0/O or 1/I/L, grouped like `K7Q4-M2XP-9R`, and match ignoring case, dashes and spaces. The server keeps only their hashes.

## Server commands

`Run serve` starts the server and runs migrations first (every command does). These are for whoever runs the box:

- `Run migrate`
- `Run bootstrap --email <e> --name <n> --farm <farm name> --tz <IANA zone>` makes the first admin (with a password nobody knows), the farm, a season named for the current year in the farm's zone (set active) and "Field 1". It prints the farm id and a one-time reset code: in the app, tap **I have a reset code** to set a password. It refuses an email that already has an account.
- `Run invite --farm <id> --role worker|admin [--note <who>]` prints an invite code.
- `Run import-artifact --farm <id> --email <user> --file <export.json>` imports a time card exported from the original web artifact for a current member, in one transaction through the same store as pushes (so devices pull it). Blocks go in the farm's first live field (or a new "Field 1"); shifts are checked with `ShiftRules`; marks claim their trees first-come-first-served on the active season. The person's name, job and rate land on their membership, and the farm's name and week start only while the farm is untouched since bootstrap. It's safe to run again: records already on the server stay as they are unless the export has a newer copy of a shift, and nothing changed or erased in the app comes back. It prints counts and notes.
- `Run backup` writes a `VACUUM INTO` copy to `timecard-YYYYMMDD-HHMMSS.sqlite` (server local time) in the backups folder, keeps the newest 30, and clears out retry answers older than 90 days, ended sessions and spent reset codes. launchd runs it nightly (`deploy/launchd/backup.plist.template`). As a safety net, the serving process checks hourly and runs the same backup when the newest one is more than 25 hours old.

Settings come from the environment: `TIMECARD_HOST` (default `127.0.0.1`), `TIMECARD_PORT` (`8790`), `TIMECARD_DB` (`./data/timecard.sqlite`; `:memory:` for a throwaway), `TIMECARD_BACKUP_DIR` (default: a `backups` folder beside the database file, so `./data/backups`), `TIMECARD_BCRYPT_COST` (`12`).
