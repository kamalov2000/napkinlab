#!/usr/bin/env bash
# Checks that stage 1 is done. Prints PASS/FAIL per item, exits 1 if anything failed.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1

N=${N:-1000000}
fails=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

echo "Проверка стадии 1"

for svc in postgres redis api; do
  id=$(docker compose ps -q "$svc" 2>/dev/null)
  state=$( [ -n "$id" ] && docker inspect -f '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id" 2>/dev/null)
  if [ "$state" = "running/healthy" ]; then pass "контейнер $svc жив ($state)"; else fail "контейнер $svc: ${state:-не запущен}"; fi
done

rows=$(docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "SELECT count(*) FROM urls"' 2>/dev/null | tr -d '[:space:]')
if [ -n "$rows" ] && [ "$rows" -ge "$N" ]; then pass "в таблице urls $rows строк (нужно ≥ $N)"; else fail "в таблице urls ${rows:-?} строк (нужно ≥ $N)"; fi

est=results/estimate.json
if [ -f "$est" ] && grep -q '"target_rps": *[0-9]' "$est" && grep -q '"expected_p95_ms": *[0-9]' "$est" \
  && grep -q '"expected_result": *"[^"]' "$est"; then
  pass "results/estimate.json заполнен"
else
  fail "results/estimate.json не заполнен (make estimate RPS=... P95=... WHY=\"...\")"
fi

if ls results/read_*.json >/dev/null 2>&1; then
  pass "есть прогон чтения: $(ls -1 results/read_*.json | wc -l | tr -d ' ') шт."
else
  fail "нет results/read_*.json (make stage1)"
fi

echo
if [ "$fails" -eq 0 ]; then echo "Стадия 1: PASS"; else echo "Стадия 1: FAIL ($fails)"; exit 1; fi
