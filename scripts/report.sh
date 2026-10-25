#!/usr/bin/env bash
# Prints "estimate vs measurement" for the latest read run. Needs only bash, grep, sed, awk.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/i18n.sh

num() { # num KEY FILE -> numeric value of "KEY": <number>
  grep -o "\"$1\": *[-0-9.e+]*" "$2" | head -1 | sed 's/.*: *//'
}
str() { # str KEY FILE -> string value of "KEY": "..."
  grep -o "\"$1\": *\".*\"" "$2" | head -1 | sed 's/^[^:]*: *"//; s/"$//; s/\\"/"/g'
}

est=results/estimate.json
[ -f "$est" ] || { echo "$(t report_no_estimate)"; exit 1; }

run=$(ls -1 results/read_*.json 2>/dev/null | sort -t_ -k3 | tail -1 || true)
[ -n "$run" ] || { echo "$(t report_no_run)"; exit 1; }

target=$(num target_rps "$est")
exp_p95=$(num expected_p95_ms "$est")
why=$(str expected_result "$est")

run_target=$(num napkin_target_rps "$run")
actual=$(num napkin_actual_rps "$run")
p95=$(num napkin_p95_ms "$run")
p99=$(num napkin_p99_ms "$run")
err=$(num napkin_error_rate "$run")
dropped=$(num napkin_dropped_iterations "$run")

echo
echo "$(t report_title "$run")"
echo
# Header is a literal: printf pads by bytes, which breaks alignment for Cyrillic.
echo "$(tf report_header)"
echo "-----------+-----------------+------------+------------+------------"
printf '%-10s | %-15s | %-10s | %-10s | %s\n' "$run_target" "$actual" "$p95" "$p99" "$(awk -v e="$err" 'BEGIN{printf "%.2f%%", e*100}')"
echo
echo "$(t report_expected "$exp_p95" "$target" "$why")"
echo "$(t report_dropped "$dropped")"
[ "$run_target" = "$target" ] || echo "$(t report_warn_rate "$run_target" "$target")"

verdict=$(awk -v p95="$p95" -v want="$exp_p95" -v err="$err" -v act="$actual" -v tgt="$target" \
  -v f_p95="$(tf verdict_p95)" -v f_err="$(tf verdict_err)" -v f_rps="$(tf verdict_rps)" -v f_ok="$(tf verdict_ok)" 'BEGIN {
  bad = 0
  if (p95 > want) { printf f_p95, p95, want, p95/want; bad = 1 }
  if (err > 0.01) { printf f_err, err*100; bad = 1 }
  if (act < tgt * 0.95) { printf f_rps, act, tgt; bad = 1 }
  if (!bad) printf "%s", f_ok
  exit bad
}') && ok=1 || ok=0

echo "$(t report_verdict "${verdict%; }")"
if [ "$ok" -eq 0 ]; then
  echo "$(t report_failed)"
fi
echo
