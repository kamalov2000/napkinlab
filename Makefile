SHELL := bash
.DEFAULT_GOAL := help

# Git Bash on Windows rewrites "/load/read.js"-style arguments into Windows paths.
export MSYS_NO_PATHCONV := 1

N        ?= 1000000
RATE     ?= 100
DURATION ?= 60s
COMPOSE  := docker compose
PSQL     := $(COMPOSE) exec -T postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -tA -c "$$0"'
RUN_AS   := --user $$(id -u):$$(id -g)

.PHONY: help up down logs seed sample estimate load-read load-write stage1 report check clean

help: ## показать список целей
	@grep -hE '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

.env:
	@cp .env.example .env

up: .env ## поднять postgres, redis, api и дождаться healthy
	@$(COMPOSE) up -d --build --wait postgres redis api
	@$(COMPOSE) ps

down: ## остановить контейнеры (данные сохраняются)
	@$(COMPOSE) down

logs: ## логи всех контейнеров (Ctrl+C — выход)
	@$(COMPOSE) logs -f

seed: .env ## вставить N записей через COPY (по умолчанию N=1000000)
	@$(COMPOSE) run --rm --build $(RUN_AS) seed -n $(N)

sample: .env ## пересоздать results/sample_codes.txt без пересева: make sample N=100000
	@$(COMPOSE) run --rm --build $(RUN_AS) -e SEED_SAMPLE=$(if $(filter command line,$(origin N)),$(N),20) seed -sample-only

estimate: ## записать оценку до замера: make estimate RPS=500 P95=20 WHY="..."
	@if [ -z "$(RPS)" ] || [ -z "$(P95)" ] || [ -z "$(WHY)" ]; then \
		echo 'Usage: make estimate RPS=500 P95=20 WHY="..."'; exit 1; fi
	@why=$$(printf '%s' "$(WHY)" | tr -d '\042\134'); \
	printf '{\n  "target_rps": %s,\n  "expected_p95_ms": %s,\n  "expected_result": "%s"\n}\n' \
		"$(RPS)" "$(P95)" "$$why" > results/estimate.json
	@cat results/estimate.json

load-read: ## k6: GET /{code} с постоянной частотой RATE запросов/с
	@$(COMPOSE) run --rm $(RUN_AS) -e RATE=$(RATE) -e DURATION=$(DURATION) k6 run --quiet /load/read.js \
		|| { rc=$$?; [ $$rc -eq 99 ] && echo "k6: thresholds crossed (a measurement result, not a launch failure)" || exit $$rc; }

load-write: ## k6: POST /shorten с постоянной частотой RATE запросов/с
	@$(COMPOSE) run --rm $(RUN_AS) -e RATE=$(RATE) -e DURATION=$(DURATION) k6 run --quiet /load/write.js \
		|| { rc=$$?; [ $$rc -eq 99 ] && echo "k6: thresholds crossed (a measurement result, not a launch failure)" || exit $$rc; }

stage1: ## стадия 1: up -> seed (если пусто) -> read на target_rps -> report
	@[ -f results/estimate.json ] || { echo 'Estimate first: make estimate RPS=... P95=... WHY="..."'; exit 1; }
	@$(MAKE) --no-print-directory up
	@rows=$$($(PSQL) "SELECT count(*) FROM urls" | tr -d '[:space:]'); \
	if [ "$$rows" = "0" ]; then $(MAKE) --no-print-directory seed N=$(N); else echo "urls already has $$rows rows, seed skipped"; fi
	@rate=$$(grep -o '"target_rps": *[0-9]*' results/estimate.json | grep -o '[0-9]*$$'); \
	$(MAKE) --no-print-directory load-read RATE=$$rate
	@$(MAKE) --no-print-directory report

report: ## таблица «оценка vs замер» по последнему прогону чтения
	@bash scripts/report.sh

check: ## проверить, что стадия 1 выполнена (PASS/FAIL)
	@N=$(N) bash scripts/check.sh

clean: ## удалить контейнеры, volumes и results (кроме .gitkeep)
	@$(COMPOSE) --profile tools down -v --remove-orphans
	@find results -type f ! -name .gitkeep -delete

-include pro/Makefile.pro
