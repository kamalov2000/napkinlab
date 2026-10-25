#!/usr/bin/env bash
# Checks that stage 1 is done. Prints PASS/FAIL per item, exits 1 if anything failed.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
source scripts/i18n.sh

N=${N:-1000000}
fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

echo "$(t check_title)"

for svc in postgres redis api; do
  id=$(docker compose ps -q "$svc" 2>/dev/null)
  state=$( [ -n "$id" ] && docker inspect -f '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id" 2>/dev/null)
  if [ "$state" = "running/healthy" ]; then pass "$(t check_container_ok "$svc" "$state")"; else fail "$(t check_container_bad "$svc" "${state:-$(t check_not_running)}")"; fi
done

rows=$(docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "SELECT count(*) FROM urls"' 2>/dev/null | tr -d '[:space:]')
if [ -n "$rows" ] && [ "$rows" -ge "$N" ]; then pass "$(t check_rows "$rows" "$N")"; else fail "$(t check_rows "${rows:-?}" "$N")"; fi

est=results/estimate.json
if [ -f "$est" ] && grep -q '"target_rps": *[0-9]' "$est" && grep -q '"expected_p95_ms": *[0-9]' "$est" \
  && grep -q '"expected_result": *"[^"]' "$est"; then
  pass "$(t check_est_ok)"
else
  fail "$(t check_est_bad)"
fi

if ls results/read_*.json >/dev/null 2>&1; then
  pass "$(t check_runs_ok "$(ls -1 results/read_*.json | wc -l | tr -d ' ')")"
else
  fail "$(t check_runs_bad)"
fi

echo
if [ "$fails" -eq 0 ]; then echo "$(t check_pass)"; else echo "$(t check_fail "$fails")"; exit 1; fi
