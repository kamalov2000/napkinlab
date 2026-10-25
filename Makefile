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

help: ## show the list of targets
	@bash scripts/i18n.sh help $(MAKEFILE_LIST)

.env:
	@cp .env.example .env

up: .env ## start postgres, redis, api and wait until healthy
	@$(COMPOSE) up -d --build --wait postgres redis api
	@$(COMPOSE) ps

down: ## stop containers (data is kept)
	@$(COMPOSE) down

logs: ## logs of all containers (Ctrl+C to exit)
	@$(COMPOSE) logs -f

seed: .env ## insert N rows via COPY (default N=1000000)
	@$(COMPOSE) run --rm --build $(RUN_AS) seed -n $(N)

sample: .env ## rewrite results/sample_codes.txt without reseeding: make sample N=100000
	@$(COMPOSE) run --rm --build $(RUN_AS) -e SEED_SAMPLE=$(if $(filter command line,$(origin N)),$(N),20) seed -sample-only

estimate: ## record the estimate before measuring: make estimate RPS=500 P95=20 WHY="..."
	@if [ -z "$(RPS)" ] || [ -z "$(P95)" ] || [ -z "$(WHY)" ]; then \
		echo 'Usage: make estimate RPS=500 P95=20 WHY="..."'; exit 1; fi
	@why=$$(printf '%s' "$(WHY)" | tr -d '\042\134'); \
	printf '{\n  "target_rps": %s,\n  "expected_p95_ms": %s,\n  "expected_result": "%s"\n}\n' \
		"$(RPS)" "$(P95)" "$$why" > results/estimate.json
	@cat results/estimate.json

load-read: ## k6: GET /{code} at a constant RATE requests/s
	@$(COMPOSE) run --rm $(RUN_AS) -e RATE=$(RATE) -e DURATION=$(DURATION) k6 run --quiet /load/read.js \
		|| { rc=$$?; [ $$rc -eq 99 ] && echo "k6: thresholds crossed (a measurement result, not a launch failure)" || exit $$rc; }

load-write: ## k6: POST /shorten at a constant RATE requests/s
	@$(COMPOSE) run --rm $(RUN_AS) -e RATE=$(RATE) -e DURATION=$(DURATION) k6 run --quiet /load/write.js \
		|| { rc=$$?; [ $$rc -eq 99 ] && echo "k6: thresholds crossed (a measurement result, not a launch failure)" || exit $$rc; }

stage1: ## stage 1: up -> seed (if empty) -> read at target_rps -> report
	@[ -f results/estimate.json ] || { echo 'Estimate first: make estimate RPS=... P95=... WHY="..."'; exit 1; }
	@$(MAKE) --no-print-directory up
	@rows=$$($(PSQL) "SELECT count(*) FROM urls" | tr -d '[:space:]'); \
	if [ "$$rows" = "0" ]; then $(MAKE) --no-print-directory seed N=$(N); else echo "urls already has $$rows rows, seed skipped"; fi
	@rate=$$(grep -o '"target_rps": *[0-9]*' results/estimate.json | grep -o '[0-9]*$$'); \
	$(MAKE) --no-print-directory load-read RATE=$$rate
	@$(MAKE) --no-print-directory report

report: ## "estimate vs. measurement" table for the latest read run
	@bash scripts/report.sh

check: ## check that stage 1 is done (PASS/FAIL)
	@N=$(N) bash scripts/check.sh

clean: ## remove containers, volumes and results (except .gitkeep)
	@$(COMPOSE) --profile tools down -v --remove-orphans
	@find results -type f ! -name .gitkeep -delete

-include pro/Makefile.pro
