#!/usr/bin/env bash
# Output language for scripts: English by default, NAPKINLAB_LANG=ru (environment or .env) for Russian.
# Sourced by scripts after they cd to the repo root:
#   t KEY [ARGS...]  — the message KEY in the current language, printf-formatted, no trailing newline
#   tf KEY           — the raw format string (for awk printf and literal table headers)
# Executed as `bash scripts/i18n.sh help Makefile ...` it prints `make help`.
#
# Plain `case` tables instead of associative arrays: they also work in bash 3.2 (macOS).
# Russian strings must stay byte-identical: they are quoted in published articles.

if [ -z "${NAPKINLAB_LANG:-}" ] && [ -f .env ]; then
  NAPKINLAB_LANG=$(sed -n 's/^NAPKINLAB_LANG=//p' .env | tr -d '"\r' | tail -1)
fi
NAPKINLAB_LANG=${NAPKINLAB_LANG:-en}
[ "$NAPKINLAB_LANG" = ru ] || NAPKINLAB_LANG=en

_msg_en_core() {
  case "$1" in
    report_no_estimate) m='No results/estimate.json — run make estimate RPS=... P95=... WHY="..." first' ;;
    report_no_run) m='No results/read_*.json — run make load-read or make stage1 first' ;;
    report_title) m='Stage 1 — estimate vs. measurement   (%s)' ;;
    report_header) m='target_rps | actual RPS      | p95, ms    | p99, ms    | error rate' ;;
    report_expected) m='Expected:  p95 ≤ %s ms at %s RPS — "%s"' ;;
    report_dropped) m='Dropped k6 iterations (ran out of VUs): %s' ;;
    report_warn_rate) m='Warning: the run was at %s RPS, but the estimate says %s RPS.' ;;
    verdict_p95) m='p95 %.1f ms against expected %s ms (%.0f× higher); ' ;;
    verdict_err) m='errors %.2f%% (> 1%%); ' ;;
    verdict_rps) m='actual RPS %.1f below target %s; ' ;;
    verdict_ok) m='within the estimate' ;;
    report_verdict) m='Estimate vs. fact: %s' ;;
    report_failed) m='The estimate did not hold. Why — stages 2 and 3.' ;;
    check_title) m='Stage 1 check' ;;
    check_container_ok) m='container %s is alive (%s)' ;;
    check_container_bad) m='container %s: %s' ;;
    check_not_running) m='not running' ;;
    check_rows) m='urls has %s rows (need ≥ %s)' ;;
    check_est_ok) m='results/estimate.json is filled in' ;;
    check_est_bad) m='results/estimate.json is not filled in (make estimate RPS=... P95=... WHY="...")' ;;
    check_runs_ok) m='read runs found: %s' ;;
    check_runs_bad) m='no results/read_*.json (make stage1)' ;;
    check_pass) m='Stage 1: PASS' ;;
    check_fail) m='Stage 1: FAIL (%s)' ;;
    *) return 1 ;;
  esac
  printf '%s' "$m"
}

_msg_ru_core() {
  case "$1" in
    report_no_estimate) m='Нет results/estimate.json — сначала make estimate RPS=... P95=... WHY="..."' ;;
    report_no_run) m='Нет results/read_*.json — сначала make load-read или make stage1' ;;
    report_title) m='Стадия 1 — оценка против замера   (%s)' ;;
    report_header) m='target_rps | фактический RPS | p95, мс    | p99, мс    | доля ошибок' ;;
    report_expected) m='Ожидание:  p95 ≤ %s мс при %s RPS — «%s»' ;;
    report_dropped) m='Пропущено итераций k6 (не хватило VU): %s' ;;
    report_warn_rate) m='Внимание: прогон был на %s RPS, а в оценке %s RPS.' ;;
    verdict_p95) m='p95 %.1f мс против ожидаемых %s мс (в %.0f раз больше); ' ;;
    verdict_err) m='ошибок %.2f%% (> 1%%); ' ;;
    verdict_rps) m='фактический RPS %.1f ниже целевого %s; ' ;;
    verdict_ok) m='уложились в оценку' ;;
    report_verdict) m='Оценка vs факт: %s' ;;
    report_failed) m='Оценка не сошлась. Почему — стадия 2 и 3.' ;;
    check_title) m='Проверка стадии 1' ;;
    check_container_ok) m='контейнер %s жив (%s)' ;;
    check_container_bad) m='контейнер %s: %s' ;;
    check_not_running) m='не запущен' ;;
    check_rows) m='в таблице urls %s строк (нужно ≥ %s)' ;;
    check_est_ok) m='results/estimate.json заполнен' ;;
    check_est_bad) m='results/estimate.json не заполнен (make estimate RPS=... P95=... WHY="...")' ;;
    check_runs_ok) m='есть прогон чтения: %s шт.' ;;
    check_runs_bad) m='нет results/read_*.json (make stage1)' ;;
    check_pass) m='Стадия 1: PASS' ;;
    check_fail) m='Стадия 1: FAIL (%s)' ;;
    # `make help`: English descriptions are the `## ...` comments in the Makefiles.
    help_help) m='показать список целей' ;;
    help_up) m='поднять postgres, redis, api и дождаться healthy' ;;
    help_down) m='остановить контейнеры (данные сохраняются)' ;;
    help_logs) m='логи всех контейнеров (Ctrl+C — выход)' ;;
    help_seed) m='вставить N записей через COPY (по умолчанию N=1000000)' ;;
    help_sample) m='пересоздать results/sample_codes.txt без пересева: make sample N=100000' ;;
    help_estimate) m='записать оценку до замера: make estimate RPS=500 P95=20 WHY="..."' ;;
    help_load-read) m='k6: GET /{code} с постоянной частотой RATE запросов/с' ;;
    help_load-write) m='k6: POST /shorten с постоянной частотой RATE запросов/с' ;;
    help_stage1) m='стадия 1: up -> seed (если пусто) -> read на target_rps -> report' ;;
    help_report) m='таблица «оценка vs замер» по последнему прогону чтения' ;;
    help_check) m='проверить, что стадия 1 выполнена (PASS/FAIL)' ;;
    help_clean) m='удалить контейнеры, volumes и results (кроме .gitkeep)' ;;
    *) return 1 ;;
  esac
  printf '%s' "$m"
}

# tf KEY: pro/scripts/i18n-pro.sh may define _msg_<lang>_pro, which is looked up first.
tf() {
  local f
  for f in "_msg_${NAPKINLAB_LANG}_pro" "_msg_${NAPKINLAB_LANG}_core"; do
    declare -F "$f" >/dev/null && "$f" "$1" && return 0
  done
  printf '%s' "$1"
}

t() {
  local fmt
  fmt=$(tf "$1"); shift
  # shellcheck disable=SC2059 # the format comes from the tables above
  printf -- "$fmt" "$@"
}

napkin_help() {
  local line target desc ru
  grep -hE '^[a-z0-9-]+:.*## ' "$@" | while IFS= read -r line; do
    target=${line%%:*}
    desc=${line#*## }
    if [ "$NAPKINLAB_LANG" = ru ]; then
      ru=$(tf "help_$target")
      [ "$ru" = "help_$target" ] || desc=$ru
    fi
    printf '  %-15s %s\n' "$target" "$desc"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = help ]; then
  shift
  [ -f pro/scripts/i18n-pro.sh ] && source pro/scripts/i18n-pro.sh
  napkin_help "$@"
fi
