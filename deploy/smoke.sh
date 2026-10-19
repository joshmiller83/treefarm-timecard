#!/bin/bash
# End-to-end check against a running server (local or public).
#   deploy/smoke.sh                 checks https://$PUBLIC_HOSTNAME
#   deploy/smoke.sh --local         checks http://$HOST:$PORT
# With SMOKE_EMAIL and SMOKE_PASSWORD set it also signs in, reads /v1/me, pulls,
# pushes a note on a tree and deletes it again, then signs out.
source "$(dirname "$0")/lib.sh"

base="https://$PUBLIC_HOSTNAME"
[[ "${1:-}" == "--local" ]] && base="$LOCAL_URL"

pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }

say "Smoke test: $base"
health="$(curl -fsS --max-time 15 "$base/health")" || fail "health check failed"
[[ "$(jq -r .status <<<"$health")" == "ok" ]] && pass "health: $health" || fail "health: $health"

code="$(curl -s -o /dev/null -w '%{http_code}' "$base/v1/me")"
[[ "$code" == "401" ]] && pass "/v1/me without a token is refused (401)" || fail "/v1/me without a token answered $code"

if [[ -z "${SMOKE_EMAIL:-}" || -z "${SMOKE_PASSWORD:-}" ]]; then
  warn "Set SMOKE_EMAIL and SMOKE_PASSWORD to test sign-in and sync too."
  exit 0
fi

login="$(jq -n --arg e "$SMOKE_EMAIL" --arg p "$SMOKE_PASSWORD" '{email:$e,password:$p,deviceName:"smoke test"}')"
auth="$(curl -fsS -H 'content-type: application/json' -d "$login" "$base/v1/auth/login")" || fail "sign-in failed"
token="$(jq -r .token <<<"$auth")"
farm="$(jq -r '.me.farms[0].id' <<<"$auth")"
user="$(jq -r '.me.user.id' <<<"$auth")"
pass "signed in as $(jq -r .me.user.displayName <<<"$auth") on $(jq -r '.me.farms[0].name' <<<"$auth")"
H=(-H "authorization: Bearer $token" -H 'content-type: application/json')

pull="$(curl -fsS "${H[@]}" "$base/v1/farms/$farm/sync/pull?since=0&limit=1000")" || fail "pull failed"
pass "pulled $(jq '.changes | length' <<<"$pull") changes"
block="$(jq -r '[.changes[].record | select(.kind=="block") | .data | select(.deletedAt == null)][0].id // empty' <<<"$pull")"

if [[ -n "$block" ]]; then
  now="$(($(date +%s) * 1000))"
  note="$(uuidgen)"
  mk() {  # mk <deletedAt in ms, or null>
    jq -n --arg m "$(uuidgen)" --arg id "$note" --arg farm "$farm" --arg block "$block" --arg user "$user" \
      --argjson now "$now" --argjson del "$1" \
      '{mutations:[{id:$m, record:{kind:"treeNote", data:{id:$id, farmId:$farm, blockId:$block, row:0, position:0,
        authorId:$user, authorName:"smoke test", body:"smoke test note", flag:"none",
        createdAt:$now, updatedAt:($now + (if $del == null then 0 else 1 end)), deletedAt:$del}}}]}'
  }
  res="$(curl -fsS "${H[@]}" -d "$(mk null)" "$base/v1/farms/$farm/sync/push")" || fail "push failed"
  [[ "$(jq -r '.results[0].status' <<<"$res")" == "applied" ]] && pass "pushed a tree note" || fail "push: $res"
  res="$(curl -fsS "${H[@]}" -d "$(mk "$now")" "$base/v1/farms/$farm/sync/push")" || fail "delete push failed"
  [[ "$(jq -r '.results[0].status' <<<"$res")" == "applied" ]] && pass "deleted the tree note" || fail "delete: $res"
else
  warn "No blocks on this farm yet; skipped the push test."
fi

curl -fsS -o /dev/null -X POST "${H[@]}" "$base/v1/auth/logout" && pass "signed out"
say "All good."
