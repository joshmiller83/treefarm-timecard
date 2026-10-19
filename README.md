# Tree Farm Time Card

A time card for people who shape trees on a tree farm: an iPhone app you can run by voice with gloves on, a lock-screen Live Activity, and a small server so a whole crew can sign in.

- **Clock in and out, take lunch and breaks** from Siri, the lock screen, or the app.
- **Mark the trees you shape**, row by row, on a map of your fields. Fields hold blocks laid out in rows and columns, and every tree can carry notes.
- **See your pace** (trees an hour, time per tree) and how much of the field is left.
- **Print a clean time card** for any week as a PDF.
- **Share one map with your crew.** Workers see their own hours; admins see everyone's.

> Status: under construction. See the [plan of record](docs/architecture.md) as it fills in.

## Layout

| Path | What's there |
|---|---|
| `Packages/TreeFarmKit` | The shared Swift package: data model, time and tree rules, sync protocol. No dependencies; builds on iOS, macOS and Linux. |
| `Server` | Vapor server with SQLite, run behind a Cloudflare Tunnel. |
| `iOS` | The SwiftUI app, its Live Activity extension and Siri intents (XcodeGen project). |
| `deploy` | launchd, tunnel and backup scripts for running the server on a Mac. |
| `docs` | Architecture, API, data model and the edge cases the tests cover. |

## Developing

Everything is built test-first. The domain rules live in `TreeFarmKit` so they're tested once, without a simulator:

```bash
swift test --package-path Packages/TreeFarmKit
```

## License

MIT
