# HTTP API

Base URL in production: `https://timecard.joshnliz.com`. Every body is JSON written with `JSONCoding` from TreeFarmKit (dates are milliseconds since 1970). The Swift types for every body live in `Packages/TreeFarmKit/Sources/TreeFarmKit/Sync/API.swift` and `SyncProtocol.swift`, so the app and server can't drift.

Authenticated routes take `Authorization: Bearer <token>`. Errors answer with an HTTP status and `APIErrorBody { error: true, reason }`, where `reason` is a sentence fit to show a person.

## Accounts

| Method | Path | Body → Answer | Notes |
|---|---|---|---|
| GET | `/health` | → `HealthResponse` | No auth. |
| POST | `/v1/auth/login` | `LoginRequest` → `AuthResponse` | Rate limited per IP and per email; repeated failures lock the account for 15 minutes. |
| POST | `/v1/auth/register` | `RegisterRequest` → `AuthResponse` | Needs a live invite code. Invite-only: there is no open signup. |
| POST | `/v1/auth/reset` | `ResetPasswordRequest` → `AuthResponse` | Reset code from an admin. Revokes every other session. |
| POST | `/v1/auth/logout` | → 204 | Revokes the calling session. |
| GET | `/v1/me` | → `MeResponse` | The user, their farms and memberships. |
| PATCH | `/v1/me` | `UpdateMeRequest` → `MeResponse` | Changing the password needs `currentPassword`. |
| DELETE | `/v1/me` | `DeleteAccountRequest` → 204 | Deletes the login. Shifts stay with the farm under the person's name. |
| GET | `/v1/me/sessions` | → `[SessionInfo]` | |
| DELETE | `/v1/me/sessions/:id` | → 204 | |

## Farm data (sync)

All farm routes check that the caller is a current member of `:farmId`.

| Method | Path | Body → Answer | Notes |
|---|---|---|---|
| POST | `/v1/farms/:farmId/sync/push` | `PushRequest` → `PushResponse` | Up to `Limits.pushBatch` mutations. One result per mutation, in order. Retrying a mutation id returns its first result. |
| GET | `/v1/farms/:farmId/sync/pull?since=<seq>&limit=<n>` | → `PullResponse` | Changes after `since` that the caller may see, oldest first. Keep pulling while `hasMore`. |
| GET | `/v1/farms/:farmId/export.csv?from=<ms>&to=<ms>&userId=<id>` | → CSV | Workers get their own shifts only; admins may pass any `userId` or leave it out for everyone. |

### Who can push what

| Record | Worker | Admin |
|---|---|---|
| `shift` | Own shifts only. | Anyone's. |
| `treeMark` | Marks on their own shifts. | Any. |
| `treeNote` | Create any; edit or delete their own. | Any. |
| `field`, `block`, `season` | No. | Yes. |
| `farm` | No. | Yes (name, time zone, week start, active season). |
| `member` | Their own `displayName`, `jobTitle`, `rateCents`. | Anyone's role and rate. The last admin can't demote themself. |

### Who can pull what

Everyone on a farm pulls the farm, seasons, fields, blocks, every tree mark and every tree note, since the map is shared. Shifts: workers pull their own, admins pull everyone's. Members: workers see names and roles; other people's email and rate come back blank (`""` and `0`).

### Rejections

A rejected mutation carries a `RejectReason` and a `message` the app shows or speaks as-is:

- `treeTaken`: another live mark holds this tree this season. First write wins. `current` is the winning mark.
- `openShiftExists`: the user already has a shift on the clock. `current` is that shift.
- `blockInUse`: a resize, move or delete would strand marks or notes.
- `invalid`: a ShiftRules or size rule failed; `message` says which.
- `forbidden`, `notFound`.

### Conflict rules

- Shifts (with their breaks) and notes: the newer `updatedAt` wins; ties go to the copy the server already has.
- Tree marks: first commit wins for a tree in a season.
- Everything is soft-deleted with `deletedAt`, so a delete is just another upsert.

## Admin

| Method | Path | Body → Answer |
|---|---|---|
| GET | `/v1/farms/:farmId/invites` | → `[InviteInfo]` (no codes) |
| POST | `/v1/farms/:farmId/invites` | `CreateInviteRequest` → `InviteInfo` with `code` (single use, 7 days) |
| DELETE | `/v1/farms/:farmId/invites/:id` | → 204 |
| POST | `/v1/farms/:farmId/members/:userId/reset` | → `ResetCodeResponse` (single use, 24 hours) |
| DELETE | `/v1/farms/:farmId/members/:userId` | → 204 (sets `removedAt`; hours stay) |

## Server commands

`Run serve` starts the server. These are for whoever runs the box:

- `Run migrate`
- `Run bootstrap --email <e> --name <n> --farm <farm name> --tz <IANA zone>` makes the first admin and farm, and prints a one-time password-reset code to sign in with.
- `Run invite --farm <id> --role worker|admin` prints an invite code.
- `Run import-artifact --farm <id> --email <user> --file <export.json>` imports a time card exported from the original web artifact. It's safe to run again.
- `Run backup` writes a `VACUUM INTO` copy to the backups folder and keeps the newest 30.
