#!/bin/bash
# One screen of everything about the running server. No sudo.
source "$(dirname "$0")/lib.sh"
set +e

for label in "$SERVER_LABEL" "$BACKUP_LABEL" "$WATCHDOG_LABEL"; do
  if launchctl print "system/$label" >/dev/null 2>&1; then
    state="$(launchctl print "system/$label" 2>/dev/null | awk -F'= ' '/^\tstate/ {print $2; exit}')"
    printf '%-34s loaded (%s)\n' "$label" "${state:-?}"
  else
    printf '%-34s not loaded\n' "$label"
  fi
done

echo
printf 'Binary:  %s (%s)\n' "$BIN" "$(cat "$DATA_DIR/bin/VERSION" 2>/dev/null || echo unknown)"
printf 'Local:   %s\n' "$(curl -fsS --max-time 5 "$LOCAL_URL/health" 2>/dev/null || echo DOWN)"
printf 'Public:  %s\n' "$(curl -fsS --max-time 10 "https://$PUBLIC_HOSTNAME/health" 2>/dev/null || echo DOWN)"
latest="$(ls -t "$DATA_DIR"/backups/*.sqlite 2>/dev/null | head -1)"
printf 'Backup:  %s\n' "${latest:-none yet}"
printf 'DB size: %s\n' "$(du -h "$DATA_DIR"/data/*.sqlite 2>/dev/null | awk '{print $1}' | head -1)"
echo
echo "Last log lines ($DATA_DIR/logs/server.log):"
tail -n 8 "$DATA_DIR/logs/server.log" 2>/dev/null
