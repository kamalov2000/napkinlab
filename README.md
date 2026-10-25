# napkinlab

A hands-on load-testing lab. You estimate the load "on a napkin" using the method from chapter 2
of Alex Xu's *System Design Interview*, then run real load against a stand on your own laptop and
compare the estimate with the measurement. The first system is the URL shortener from chapter 8.

For people who have read about back-of-the-envelope estimation and want to find out how well their
numbers match the behaviour of a live system.

Not for you if you don't have Docker.

[Русская версия README](README.ru.md)

## Requirements

- Docker Desktop with WSL2 (or Docker on Linux/macOS);
- 4 GB of free memory;
- `make` (and `bash` — present in WSL, Linux, macOS and Git Bash).

## Quick start

```bash
make up
make seed N=1000000
make estimate RPS=500 P95=20 WHY="will hold: simple query, only a million rows"
make stage1
make check
```

`make help` lists every target. Details on running the stand — [lab/00-start.md](lab/00-start.md).

## Stage 1: estimate vs. measurement

The stand: a Go service (`POST /shorten`, `GET /{code}` → redirect), PostgreSQL with a million
links, Redis (cache off), k6 for load. Everything in Docker Compose.

You fill in the worksheet [lab/01-estimate.md](lab/01-estimate.md): compute RPS and data volume,
and **before** running anything write down your bet — what RPS the stand will sustain and what the
p95 latency will be. `make stage1` sends read load at that RPS for 60 seconds and prints the
comparison. Example `make report`:

```
Stage 1 — estimate vs. measurement   (results/read_500rps_20261024T190524.json)

target_rps | actual RPS      | p95, ms    | p99, ms    | error rate
-----------+-----------------+------------+------------+------------
500        | 24.14           | 20979.81   | 21199.99   | 0.00%

Expected:  p95 ≤ 20 ms at 500 RPS — "will hold: simple query, only a million rows"
Dropped k6 iterations (ran out of VUs): 28077
Estimate vs. fact: p95 20979.8 ms against expected 20 ms (1049× higher); actual RPS 24.1 below target 500
The estimate did not hold. Why — stages 2 and 3.
```

The gap is the expected outcome, not a broken stand. At the end of the stage you have your own
estimate, a measurement, and one concrete question: why do they differ?

## Stages 2–5

In stage 2 you find the system's limit — the RPS at which latency starts to climb; in stage 3 you
diagnose the bottleneck from metrics and the query plan; in stage 4 you make exactly one change;
in stage 5 you measure again and check whether the result confirms your explanation.

Access to stages 2–5 — $19, one-time, card payment: https://web.tribute.tg/p/I5O
After payment you get a link to an archive with a `pro/` folder; drop it into the root of this
repository and `make help` shows the new targets. (Для России — 990 ₽: https://web.tribute.tg/p/I4T)

## Caveat

Numbers from a laptop do not transfer to production: different hardware, network, database
configuration and neighbouring processes. The goal is to see the link between an estimate and
the system's behaviour, not to obtain absolute figures.

## License

MIT, see [LICENSE](LICENSE).
