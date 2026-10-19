# Architecture

## The pieces

```
                ┌──────────────── iPhone ─────────────────┐
  Siri ───────▶ │ App Intents ─┐                          │
  Lock screen ▶ │ Live Activity├─▶ FieldActions ─▶ Store  │──sync──▶ Server ─▶ SQLite
  Action btn ─▶ │ Controls ────┘   (TreeFarmKit    (GRDB  │  push/pull  (Vapor, behind
  The app ────▶ │ SwiftUI ─────┘    FieldEngine)  + outbox)│           Cloudflare Tunnel)
                └──────────────────────────────────────────┘
```

- **TreeFarmKit** (`Packages/TreeFarmKit`) is pure Swift with no dependencies, built for iOS, macOS and Linux. It holds the data model, every rule (time math, shift validation, tree marking, the row walker, map geometry, pace, reports, Siri wording) and the sync protocol. The app and the server both link it, so a rule is written and tested once.
- **The server** (`Server`) is Vapor with SQLite. It owns accounts, invites and sessions, enforces who may change what, keeps tree marks first-come-first-served, and hands each device the changes it hasn't seen.
- **The app** (`iOS`) is SwiftUI. `TimeCardCore` (a local package) holds the store, the sync engine, the API client and auth, so it's tested with `swift test` without a simulator. The app target is views plus App Intents. The widget extension holds the Live Activity and the Control Center controls.

## One action layer

Gloves make voice the main control. Every way of doing something — Siri, a Live Activity button, a Control Center control, an in-app button — goes through the same `FieldEngine` in TreeFarmKit. It takes the current state and a command (clock in, mark the next row, start lunch, undo…) and returns:

- the records to save (they go to the local store and the outbox in one transaction),
- the new work position (which row is next),
- an undo entry,
- the sentence to speak or show.

So Siri and the lock screen can't drift apart, and every message a person hears is covered by tests.

## Offline first

Fields have bad reception. Every change is saved on the phone first and queued in an outbox. The sync engine pushes the outbox in batches and pulls changes after its last cursor. Records are only ever upserted, never hard-deleted, so a delete is a record with `deletedAt` set. Conflicts settle like this:

- **Shifts and notes:** the newer `updatedAt` wins.
- **Tree marks:** the first one the server sees wins. The other person's phone drops its copy and says who shaped the tree and when.
- **Pending local edits** beat pulled copies until they're pushed.

## The lock screen while locked

Live Activity buttons and Siri run while the phone is locked. The database therefore uses the `completeUntilFirstUserAuthentication` protection class and the token sits in the Keychain as `afterFirstUnlock`. Both are readable after the first unlock following a reboot. Before that first unlock, an intent says "Unlock your phone once, then try again." A process woken then keeps a model that couldn't open its data; once the phone is unlocked, the next intent or the app coming forward opens the database again (`AppModel.reopenIfSealed`), and that model becomes the one the window, Siri and the lock screen share.

## Data shape

```
Farm ─┬─ Season (tree marks belong to one)
      ├─ Member (role, rate)
      └─ Field ─ Block (gridRow, gridColumn, rows × trees, across|down)
                   └─ tree = (blockId, row, position)   ← TreeMark (per season), TreeNote (forever)
User ─ Shift (breaks inside) ─ TreeMark
```

The full model is in `Packages/TreeFarmKit/Sources/TreeFarmKit/Model/Model.swift`, and the wire format and routes are in [api.md](api.md).
