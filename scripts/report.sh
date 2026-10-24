#!/usr/bin/env bash
# Prints "estimate vs measurement" for the latest read run. Needs only bash, grep, sed, awk.
set -euo pipefail
cd "$(dirname "$0")/.."

num() { # num KEY FILE -> numeric value of "KEY": <number>
  grep -o "\"$1\": *[-0-9.e+]*" "$2" | head -1 | sed 's/.*: *//'
}
str() { # str KEY FILE -> string value of "KEY": "..."
  grep -o "\"$1\": *\".*\"" "$2" | head -1 | sed 's/^[^:]*: *"//; s/"$//; s/\\"/"/g'
}

est=results/estimate.json
[ -f "$est" ] || { echo 'Нет results/estimate.json — сначала make estimate RPS=... P95=... WHY="..."'; exit 1; }

run=$(ls -1 results/read_*.json 2>/dev/null | sort -t_ -k3 | tail -1 || true)
[ -n "$run" ] || { echo 'Нет results/read_*.json — сначала make load-read или make stage1'; exit 1; }

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
echo "Стадия 1 — оценка против замера   ($run)"
echo
# Header is a literal: printf pads by bytes, which breaks alignment for Cyrillic.
echo "target_rps | фактический RPS | p95, мс    | p99, мс    | доля ошибок"
echo "-----------+-----------------+------------+------------+------------"
printf '%-10s | %-15s | %-10s | %-10s | %s\n' "$run_target" "$actual" "$p95" "$p99" "$(awk -v e="$err" 'BEGIN{printf "%.2f%%", e*100}')"
echo
echo "Ожидание:  p95 ≤ ${exp_p95} мс при ${target} RPS — «${why}»"
echo "Пропущено итераций k6 (не хватило VU): ${dropped}"
[ "$run_target" = "$target" ] || echo "Внимание: прогон был на ${run_target} RPS, а в оценке ${target} RPS."

verdict=$(awk -v p95="$p95" -v want="$exp_p95" -v err="$err" -v act="$actual" -v tgt="$target" 'BEGIN {
  bad = 0
  if (p95 > want) { printf "p95 %.1f мс против ожидаемых %s мс (в %.0f раз больше); ", p95, want, p95/want; bad = 1 }
  if (err > 0.01) { printf "ошибок %.2f%% (> 1%%); ", err*100; bad = 1 }
  if (act < tgt * 0.95) { printf "фактический RPS %.1f ниже целевого %s; ", act, tgt; bad = 1 }
  if (!bad) printf "уложились в оценку"
  exit bad
}') && ok=1 || ok=0

echo "Оценка vs факт: ${verdict%; }"
if [ "$ok" -eq 0 ]; then
  echo "Оценка не сошлась. Почему — стадия 2 и 3."
fi
echo
