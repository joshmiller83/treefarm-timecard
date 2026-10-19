# Running the server on a Mac

The server is one native binary plus one SQLite file. On a Mac it runs as a launchd system daemon (it starts at boot without anyone logging in) and is published through an existing Cloudflare Tunnel, so nothing listens on the open internet.

```
iPhone ──https──▶ Cloudflare ──tunnel──▶ cloudflared (on the Mac) ──▶ 127.0.0.1:8790 ──▶ server ──▶ timecard.sqlite
```

## First time

1. Copy `deploy/config.env.example` to `deploy/config.env` and fill it in. It's git-ignored.
2. Build and stage the binary. This runs the server tests first, then copies the release build to `$DATA_DIR/bin`. No sudo needed.
   ```bash
   deploy/build.sh
   ```
3. Install the daemons: the server, a 3:15 AM backup and a watchdog that restarts a hung server. This needs sudo.
   ```bash
   sudo deploy/install-services.sh
   ```
4. Create the first admin and farm. It prints a reset code. Open the app, tap **I have a reset code**, and use that code to set your password.
   ```bash
   cd ~/TreeFarmServer && TIMECARD_DB=~/TreeFarmServer/data/timecard.sqlite bin/Run bootstrap \
     --email you@example.com --name "Your Name" --farm "Your Farm" --tz America/Indiana/Indianapolis
   ```
5. Publish it through your tunnel. This adds the ingress rule and DNS record, then prints the one sudo command that restarts `cloudflared`.
   ```bash
   deploy/tunnel-add-hostname.sh
   ```
6. Check it end to end:
   ```bash
   SMOKE_EMAIL=you@example.com SMOKE_PASSWORD='…' deploy/smoke.sh
   ```

## Every update

This tests, builds, swaps the binary and restarts the server. It needs no sudo, because the daemon runs as your user and launchd restarts it right away.

```bash
deploy/update.sh
```

## Day to day

- `deploy/status.sh` shows daemon states, local and public health, the newest backup and recent log lines.
- Logs are in `$DATA_DIR/logs/` (server, backup, watchdog). The watchdog rotates them at 20 MB.
- Backups are in `$DATA_DIR/backups/`, one per night, and the newest 30 are kept. To restore one, stop the server (`sudo launchctl bootout system/<prefix>.timecard`), copy the backup over `data/timecard.sqlite`, then rerun `sudo deploy/install-services.sh`.
- To invite someone, use the app's Team tab or run `bin/Run invite --farm <farm id> --role worker`.
- If a sign-in code expired, or an admin is locked out, run `bin/Run reset-code --email <email>` for a new one.

## Notes

- **The home router caches DNS misses.** If the new hostname doesn't resolve right away, check public DNS over HTTPS (the script prints the command) rather than with `dig`.
- **FileVault and power outages.** With FileVault on, a Mac that restarts after a power cut waits at the unlock screen, so nothing starts until someone types the password.
