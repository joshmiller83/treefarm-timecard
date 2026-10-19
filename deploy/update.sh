#!/bin/bash
# Ship a new server build: test, build, swap the binary, restart, check health. No sudo:
# the daemon runs as $SERVICE_USER, so that user can stop it and launchd's KeepAlive
# starts the new binary right away.
source "$(dirname "$0")/lib.sh"

"$DEPLOY_DIR/build.sh"

if pgrep -u "$SERVICE_USER" -f "$BIN serve" >/dev/null; then
  say "Restarting the server"
  pkill -TERM -u "$SERVICE_USER" -f "$BIN serve"
else
  warn "The server isn't running. Install the daemons with: sudo deploy/install-services.sh"
  exit 1
fi

sleep 2
wait_for_health 60 || die "The new build didn't come up. See $DATA_DIR/logs/server.log"
say "Running $(cat "$DATA_DIR/bin/VERSION"): $(curl -fsS "$LOCAL_URL/health")"
